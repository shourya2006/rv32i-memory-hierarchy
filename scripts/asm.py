#!/usr/bin/env python3
"""Small RV32I assembler for the project's test programs.

    python3 scripts/asm.py programs/sum.s build/sum.hex

    python3 scripts/asm.py programs/qsort.s build/qsort      # writes qsort.code.hex and qsort.data.hex

Supports the RV32I base integer instructions except ECALL, EBREAK and the
CSR instructions, plus FENCE, FENCE.I and the pseudo-instructions nop, li,
la, mv, not, neg, seqz, snez, j, call, ret, beqz, bnez, bgt, ble, bgtu and
bleu. A line may hold a label ("loop:"), an instruction and a '#' comment.

Sections: code goes in .text (from 0x0000_0000), data in .data (from
0x1000_0000) with .word (numbers or labels) and .space (bytes). Each
output file has one 32-bit word per line in hex, the format Verilog's
$readmemh reads.
"""

import sys

TEXT_BASE = 0x0000_0000
DATA_BASE = 0x1000_0000

ABI_NAMES = [
    "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
]

# mnemonic: (funct3, funct7)
R_TYPE = {
    "add": (0b000, 0b0000000), "sub": (0b000, 0b0100000),
    "sll": (0b001, 0b0000000), "slt": (0b010, 0b0000000),
    "sltu": (0b011, 0b0000000), "xor": (0b100, 0b0000000),
    "srl": (0b101, 0b0000000), "sra": (0b101, 0b0100000),
    "or": (0b110, 0b0000000), "and": (0b111, 0b0000000),
}
SHIFT_IMM = {"slli": (0b001, 0b0000000), "srli": (0b101, 0b0000000), "srai": (0b101, 0b0100000)}

# mnemonic: funct3
I_ALU = {"addi": 0b000, "slti": 0b010, "sltiu": 0b011, "xori": 0b100, "ori": 0b110, "andi": 0b111}
LOADS = {"lb": 0b000, "lh": 0b001, "lw": 0b010, "lbu": 0b100, "lhu": 0b101}
STORES = {"sb": 0b000, "sh": 0b001, "sw": 0b010}
BRANCHES = {"beq": 0b000, "bne": 0b001, "blt": 0b100, "bge": 0b101, "bltu": 0b110, "bgeu": 0b111}

OP_LUI = 0b0110111
OP_AUIPC = 0b0010111
OP_JAL = 0b1101111
OP_JALR = 0b1100111
OP_BRANCH = 0b1100011
OP_LOAD = 0b0000011
OP_STORE = 0b0100011
OP_ALU_IMM = 0b0010011
OP_ALU_REG = 0b0110011


class AsmError(Exception):
    pass


def reg(text):
    text = text.strip()
    if text in ABI_NAMES:
        return ABI_NAMES.index(text)
    if text == "fp":
        return 8
    if text.startswith("x") and text[1:].isdigit() and int(text[1:]) < 32:
        return int(text[1:])
    raise AsmError(f"unknown register '{text}'")


def number(text):
    try:
        return int(text.strip(), 0)
    except ValueError:
        raise AsmError(f"bad number '{text}'")


def fits(value, bits):
    return -(1 << (bits - 1)) <= value < (1 << (bits - 1))


def mem_operand(text):
    """'8(sp)' -> (8, 2)"""
    text = text.strip()
    if "(" not in text or not text.endswith(")"):
        raise AsmError(f"expected offset(register), got '{text}'")
    offset_text, reg_text = text[:-1].split("(")
    offset = 0
    if offset_text.strip():
        offset = number(offset_text)
    return offset, reg(reg_text)


def label_offset(text, labels, address):
    text = text.strip()
    if text not in labels:
        raise AsmError(f"unknown label '{text}'")
    return labels[text] - address


def encode_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_i(imm, rs1, funct3, rd, opcode):
    if not fits(imm, 12):
        raise AsmError(f"immediate {imm} does not fit in 12 bits")
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_s(imm, rs2, rs1, funct3):
    if not fits(imm, 12):
        raise AsmError(f"offset {imm} does not fit in 12 bits")
    imm = imm & 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 0x1F) << 7) | OP_STORE


def encode_b(offset, rs2, rs1, funct3):
    if not fits(offset, 13) or offset % 2 != 0:
        raise AsmError(f"branch offset {offset} is out of range")
    imm = offset & 0x1FFF
    bit12 = (imm >> 12) & 0x1
    bit11 = (imm >> 11) & 0x1
    bits10_5 = (imm >> 5) & 0x3F
    bits4_1 = (imm >> 1) & 0xF
    return ((bit12 << 31) | (bits10_5 << 25) | (rs2 << 20) | (rs1 << 15)
            | (funct3 << 12) | (bits4_1 << 8) | (bit11 << 7) | OP_BRANCH)


def encode_u(imm20, rd, opcode):
    if not 0 <= imm20 <= 0xFFFFF:
        raise AsmError(f"upper immediate {imm20} does not fit in 20 bits")
    return (imm20 << 12) | (rd << 7) | opcode


def encode_j(offset, rd):
    if not fits(offset, 21) or offset % 2 != 0:
        raise AsmError(f"jump offset {offset} is out of range")
    imm = offset & 0x1FFFFF
    bit20 = (imm >> 20) & 0x1
    bits10_1 = (imm >> 1) & 0x3FF
    bit11 = (imm >> 11) & 0x1
    bits19_12 = (imm >> 12) & 0xFF
    return (bit20 << 31) | (bits10_1 << 21) | (bit11 << 20) | (bits19_12 << 12) | (rd << 7) | OP_JAL


def split_constant(value):
    """Return (upper, lower) with (upper << 12) + lower == value, for lui + addi."""
    value = value & 0xFFFFFFFF
    lower = value & 0xFFF
    if lower >= 0x800:
        lower -= 0x1000          # addi sign-extends, so borrow from the upper part
    upper = ((value - lower) >> 12) & 0xFFFFF
    return upper, lower


def word_count(mnemonic, operands):
    if mnemonic == "la":
        return 2
    if mnemonic == "li" and len(operands) == 2 and not fits(number(operands[1]), 12):
        return 2
    return 1


def symbol_or_number(text, labels):
    text = text.strip()
    if text in labels:
        return labels[text]
    return number(text)


def encode(mnemonic, ops, address, labels):
    """Return the machine words for one instruction."""

    def need(count):
        if len(ops) != count:
            raise AsmError(f"'{mnemonic}' takes {count} operands, got {len(ops)}")

    if mnemonic in R_TYPE:
        need(3)
        funct3, funct7 = R_TYPE[mnemonic]
        return [encode_r(funct7, reg(ops[2]), reg(ops[1]), funct3, reg(ops[0]), OP_ALU_REG)]
    if mnemonic in SHIFT_IMM:
        need(3)
        funct3, funct7 = SHIFT_IMM[mnemonic]
        shamt = number(ops[2])
        if not 0 <= shamt < 32:
            raise AsmError(f"shift amount {shamt} is out of range")
        return [encode_r(funct7, shamt, reg(ops[1]), funct3, reg(ops[0]), OP_ALU_IMM)]
    if mnemonic in I_ALU:
        need(3)
        return [encode_i(number(ops[2]), reg(ops[1]), I_ALU[mnemonic], reg(ops[0]), OP_ALU_IMM)]
    if mnemonic in LOADS:
        need(2)
        offset, base = mem_operand(ops[1])
        return [encode_i(offset, base, LOADS[mnemonic], reg(ops[0]), OP_LOAD)]
    if mnemonic in STORES:
        need(2)
        offset, base = mem_operand(ops[1])
        return [encode_s(offset, reg(ops[0]), base, STORES[mnemonic])]
    if mnemonic in BRANCHES:
        need(3)
        offset = label_offset(ops[2], labels, address)
        return [encode_b(offset, reg(ops[1]), reg(ops[0]), BRANCHES[mnemonic])]
    if mnemonic == "lui":
        need(2)
        return [encode_u(number(ops[1]), reg(ops[0]), OP_LUI)]
    if mnemonic == "auipc":
        need(2)
        return [encode_u(number(ops[1]), reg(ops[0]), OP_AUIPC)]
    if mnemonic == "jal":
        need(2)
        return [encode_j(label_offset(ops[1], labels, address), reg(ops[0]))]
    if mnemonic == "fence":
        return [0x0FF0000F]                     # fence iorw, iorw
    if mnemonic == "fence.i":
        need(0)
        return [0x0000100F]
    if mnemonic == "jalr":
        need(2)
        offset, base = mem_operand(ops[1])
        return [encode_i(offset, base, 0b000, reg(ops[0]), OP_JALR)]

    # Pseudo-instructions
    if mnemonic == "nop":
        need(0)
        return [encode_i(0, 0, 0b000, 0, OP_ALU_IMM)]
    if mnemonic == "mv":
        need(2)
        return [encode_i(0, reg(ops[1]), 0b000, reg(ops[0]), OP_ALU_IMM)]
    if mnemonic == "j":
        need(1)
        return [encode_j(label_offset(ops[0], labels, address), 0)]
    if mnemonic == "call":
        need(1)
        return [encode_j(label_offset(ops[0], labels, address), 1)]
    if mnemonic == "ret":
        need(0)
        return [encode_i(0, 1, 0b000, 0, OP_JALR)]
    if mnemonic == "not":
        need(2)
        return [encode_i(-1, reg(ops[1]), I_ALU["xori"], reg(ops[0]), OP_ALU_IMM)]
    if mnemonic == "neg":
        need(2)
        funct3, funct7 = R_TYPE["sub"]
        return [encode_r(funct7, reg(ops[1]), 0, funct3, reg(ops[0]), OP_ALU_REG)]
    if mnemonic == "seqz":
        need(2)
        return [encode_i(1, reg(ops[1]), I_ALU["sltiu"], reg(ops[0]), OP_ALU_IMM)]
    if mnemonic == "snez":
        need(2)
        funct3, funct7 = R_TYPE["sltu"]
        return [encode_r(funct7, reg(ops[1]), 0, funct3, reg(ops[0]), OP_ALU_REG)]
    if mnemonic in ("bgt", "ble", "bgtu", "bleu"):
        need(3)
        real = {"bgt": "blt", "ble": "bge", "bgtu": "bltu", "bleu": "bgeu"}[mnemonic]
        offset = label_offset(ops[2], labels, address)
        return [encode_b(offset, reg(ops[0]), reg(ops[1]), BRANCHES[real])]   # operands swapped
    if mnemonic == "la":
        need(2)
        rd = reg(ops[0])
        upper, lower = split_constant(symbol_or_number(ops[1], labels))
        return [encode_u(upper, rd, OP_LUI), encode_i(lower, rd, 0b000, rd, OP_ALU_IMM)]
    if mnemonic == "beqz":
        need(2)
        return [encode_b(label_offset(ops[1], labels, address), 0, reg(ops[0]), BRANCHES["beq"])]
    if mnemonic == "bnez":
        need(2)
        return [encode_b(label_offset(ops[1], labels, address), 0, reg(ops[0]), BRANCHES["bne"])]
    if mnemonic == "li":
        need(2)
        rd = reg(ops[0])
        value = number(ops[1])
        if fits(value, 12):
            return [encode_i(value, 0, 0b000, rd, OP_ALU_IMM)]
        upper, lower = split_constant(value)
        return [encode_u(upper, rd, OP_LUI), encode_i(lower, rd, 0b000, rd, OP_ALU_IMM)]

    raise AsmError(f"unknown instruction '{mnemonic}'")


def parse(source):
    """First pass: give every label an address and collect code lines and data items."""
    labels = {}
    instructions = []
    data_items = []
    section = "text"
    address = {"text": TEXT_BASE, "data": DATA_BASE}
    for line_no, line in enumerate(source.splitlines(), start=1):
        text = line.split("#")[0].strip()
        while ":" in text:
            label, text = text.split(":", 1)
            label = label.strip()
            text = text.strip()
            if label in labels:
                raise AsmError(f"line {line_no}: label '{label}' is defined twice")
            labels[label] = address[section]
        if not text:
            continue
        parts = text.split(None, 1)
        mnemonic = parts[0].lower()
        operands = []
        if len(parts) == 2:
            operands = [operand.strip() for operand in parts[1].split(",")]
        try:
            if mnemonic in (".text", ".data"):
                section = mnemonic[1:]
            elif mnemonic == ".word":
                if section != "data":
                    raise AsmError(".word is only allowed in .data")
                data_items.append((line_no, operands))
                address["data"] += 4 * len(operands)
            elif mnemonic == ".space":
                size = number(operands[0])
                if section != "data" or size % 4 != 0:
                    raise AsmError(".space needs .data and a multiple of 4 bytes")
                data_items.append((line_no, ["0"] * (size // 4)))
                address["data"] += size
            elif section != "text":
                raise AsmError(f"instruction '{mnemonic}' outside .text")
            else:
                instructions.append((line_no, address["text"], mnemonic, operands, text))
                address["text"] += 4 * word_count(mnemonic, operands)
        except AsmError as error:
            raise AsmError(f"line {line_no}: {error}")
    return labels, instructions, data_items


def assemble(source):
    """Return (program, data): program is a list of (word, source text), data a list of words."""
    labels, instructions, data_items = parse(source)
    program = []
    for line_no, address, mnemonic, operands, text in instructions:
        try:
            words = encode(mnemonic, operands, address, labels)
        except AsmError as error:
            raise AsmError(f"line {line_no}: {error}")
        for word in words:
            program.append((word, text))
    data = []
    for line_no, operands in data_items:
        for operand in operands:
            try:
                data.append(symbol_or_number(operand, labels) & 0xFFFFFFFF)
            except AsmError as error:
                raise AsmError(f"line {line_no}: {error}")
    return program, data


def write_hex(path, words):
    with open(path, "w") as hex_file:
        for word in words:
            hex_file.write(f"{word:08x}\n")


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: asm.py <input.s> <output prefix>")
    with open(sys.argv[1]) as source_file:
        source = source_file.read()
    try:
        program, data = assemble(source)
    except AsmError as error:
        sys.exit(f"{sys.argv[1]}: {error}")
    write_hex(sys.argv[2] + ".code.hex", [word for word, _ in program])
    write_hex(sys.argv[2] + ".data.hex", data)
    print(f"{sys.argv[2]}: {len(program)} code words, {len(data)} data words")


if __name__ == "__main__":
    main()
