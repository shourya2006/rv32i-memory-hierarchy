#!/usr/bin/env python3
"""Reference instruction-set simulator for RV32I (the "golden model").

    python3 scripts/iss.py build/qsort.code.hex build/qsort.data.hex

Runs a program image on the project memory map, one instruction at a time,
with no pipeline and no caches: exactly what the ISA says should happen.
The RTL testbench prints the same commit log (every retired instruction and
the register it wrote, plus every store), and verify.py compares the two.

With harvard=True, a load or store to the code region is a bus error, as in
the Harvard system. Otherwise memory is one coherent store, so FENCE.I has
nothing to do.
"""

import sys

CODE_BASE = 0x0000_0000
DATA_BASE = 0x1000_0000
IO_BASE = 0x2000_0000
REGION_SIZE = 16 * 1024
HALT = 0x0000006F                 # "j ." ends a program
MASK32 = 0xFFFF_FFFF


class BusError(Exception):
    pass


def sign_extend(value, bits):
    sign = 1 << (bits - 1)
    return (value & (sign - 1)) - (value & sign)


def read_hex(path):
    words = []
    if path:
        with open(path) as hex_file:
            for line in hex_file:
                line = line.strip()
                if line:
                    words.append(int(line, 16))
    return words


class Machine:
    def __init__(self, code_words, data_words, harvard=False):
        self.harvard = harvard
        self.memory = bytearray(2 * REGION_SIZE)       # code half, then data half
        for index, word in enumerate(code_words):
            self.memory[4 * index:4 * index + 4] = word.to_bytes(4, "little")
        for index, word in enumerate(data_words):
            offset = REGION_SIZE + 4 * index
            self.memory[offset:offset + 4] = word.to_bytes(4, "little")
        self.regs = [0] * 32
        self.pc = 0
        self.commits = []          # (pc, rd, value); rd = 0 when nothing is written
        self.stores = []           # (address, strobe, data on the enabled lanes)
        self.outputs = []
        self.loads = 0

    def offset(self, address, is_fetch):
        if CODE_BASE <= address < CODE_BASE + REGION_SIZE:
            if self.harvard and not is_fetch:
                raise BusError(f"data access to code address {address:#010x}")
            return address - CODE_BASE
        if DATA_BASE <= address < DATA_BASE + REGION_SIZE:
            return REGION_SIZE + address - DATA_BASE
        raise BusError(f"unmapped address {address:#010x}")

    def load(self, address, size):
        offset = self.offset(address & ~3, False) + (address & 3)
        self.loads += 1
        return int.from_bytes(self.memory[offset:offset + size], "little")

    def store(self, address, size, value):
        lane = address & 3
        strobe = ((1 << size) - 1) << lane
        lanes = 0
        for byte in range(4):
            if strobe & (1 << byte):
                lanes |= ((value >> (8 * (byte - lane))) & 0xFF) << (8 * byte)
        self.stores.append((address & MASK32, strobe, lanes))
        if IO_BASE <= address < IO_BASE + 0x1000:
            self.outputs.append(value & MASK32)
            return
        offset = self.offset(address & ~3, False)
        for byte in range(4):
            if strobe & (1 << byte):
                self.memory[offset + byte] = (lanes >> (8 * byte)) & 0xFF

    def step(self):
        """Run one instruction. Return False at the halt loop."""
        offset = self.offset(self.pc, True)
        instr = int.from_bytes(self.memory[offset:offset + 4], "little")
        if instr == HALT:
            return False

        opcode = instr & 0x7F
        rd = (instr >> 7) & 0x1F
        funct3 = (instr >> 12) & 0x7
        rs1 = self.regs[(instr >> 15) & 0x1F]
        rs2 = self.regs[(instr >> 20) & 0x1F]
        funct7 = instr >> 25
        imm_i = sign_extend(instr >> 20, 12)
        imm_s = sign_extend(((instr >> 25) << 5) | ((instr >> 7) & 0x1F), 12)
        imm_b = sign_extend((((instr >> 31) & 1) << 12) | (((instr >> 7) & 1) << 11)
                            | (((instr >> 25) & 0x3F) << 5) | (((instr >> 8) & 0xF) << 1), 13)
        imm_u = instr & 0xFFFFF000
        imm_j = sign_extend((((instr >> 31) & 1) << 20) | (((instr >> 12) & 0xFF) << 12)
                            | (((instr >> 20) & 1) << 11) | (((instr >> 21) & 0x3FF) << 1), 21)

        next_pc = (self.pc + 4) & MASK32
        result = None                                   # value written to rd

        if opcode == 0b0110111:                         # LUI
            result = imm_u
        elif opcode == 0b0010111:                       # AUIPC
            result = self.pc + imm_u
        elif opcode == 0b1101111:                       # JAL
            result = self.pc + 4
            next_pc = (self.pc + imm_j) & MASK32
        elif opcode == 0b1100111:                       # JALR
            result = self.pc + 4
            next_pc = (rs1 + imm_i) & MASK32 & ~1
        elif opcode == 0b1100011:                       # branches
            signed1 = sign_extend(rs1, 32)
            signed2 = sign_extend(rs2, 32)
            taken = {0: rs1 == rs2, 1: rs1 != rs2, 4: signed1 < signed2,
                     5: signed1 >= signed2, 6: rs1 < rs2, 7: rs1 >= rs2}[funct3]
            if taken:
                next_pc = (self.pc + imm_b) & MASK32
        elif opcode == 0b0000011:                       # loads
            address = (rs1 + imm_i) & MASK32
            if funct3 == 0:
                result = sign_extend(self.load(address, 1), 8)
            elif funct3 == 1:
                result = sign_extend(self.load(address, 2), 16)
            elif funct3 == 2:
                result = self.load(address, 4)
            elif funct3 == 4:
                result = self.load(address, 1)
            else:
                result = self.load(address, 2)
        elif opcode == 0b0100011:                       # stores
            address = (rs1 + imm_s) & MASK32
            self.store(address, 1 << funct3, rs2)
        elif opcode in (0b0010011, 0b0110011):          # ALU
            b = imm_i if opcode == 0b0010011 else rs2
            b &= MASK32
            shamt = b & 0x1F
            subtract = opcode == 0b0110011 and funct7 == 0x20
            arithmetic_shift = funct7 == 0x20
            if funct3 == 0:
                result = rs1 - b if subtract else rs1 + b
            elif funct3 == 1:
                result = rs1 << shamt
            elif funct3 == 2:
                result = int(sign_extend(rs1, 32) < sign_extend(b, 32))
            elif funct3 == 3:
                result = int(rs1 < b)
            elif funct3 == 4:
                result = rs1 ^ b
            elif funct3 == 5:
                result = (sign_extend(rs1, 32) >> shamt) if arithmetic_shift else (rs1 >> shamt)
            elif funct3 == 6:
                result = rs1 | b
            else:
                result = rs1 & b
        elif opcode == 0b0001111:                       # FENCE, FENCE.I: memory is coherent here
            pass
        else:
            raise ValueError(f"illegal instruction {instr:#010x} at {self.pc:#010x}")

        if result is not None and rd != 0:
            self.regs[rd] = result & MASK32
            self.commits.append((self.pc, rd, self.regs[rd]))
        else:
            self.commits.append((self.pc, 0, 0))
        self.pc = next_pc
        return True

    def run(self, limit=2_000_000):
        """Run to the halt loop. Return None, or the bus error message."""
        try:
            for _ in range(limit):
                if not self.step():
                    return None
        except BusError as error:
            return str(error)
        raise RuntimeError("program did not reach the halt loop")


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: iss.py <code.hex> [data.hex]")
    data_path = sys.argv[2] if len(sys.argv) > 2 else None
    machine = Machine(read_hex(sys.argv[1]), read_hex(data_path))
    error = machine.run()
    for value in machine.outputs:
        print(f"OUT {value:08x}")
    print(f"instructions={len(machine.commits)} loads={machine.loads} stores={len(machine.stores)}")
    if error:
        print("BUS_ERROR", error)


if __name__ == "__main__":
    main()
