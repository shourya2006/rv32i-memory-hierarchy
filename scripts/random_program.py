#!/usr/bin/env python3
"""Random RV32I test programs, for co-simulation against iss.py.

    python3 scripts/random_program.py 7 > build/random/rand7.s

A program loads random values into a small pool of registers, then runs a
few hundred random instructions: ALU operations, loads and stores into a
4 KB data window, forward branches and jumps, JALR, and the odd FENCE.I.
The small register pool makes back-to-back dependencies (forwarding,
load-use stalls) common, and the 4 KB window makes data-cache conflicts
common. Every branch and jump goes forward, so every program ends.
"""

import random
import sys

POOL = ["ra", "t0", "t1", "t2", "a0", "a1", "a2", "a3", "a4", "a5"]   # never s0, s1, t6
R_OPS = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
I_OPS = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
SHIFT_OPS = ["slli", "srli", "srai"]
BRANCHES = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]
LOADS = {"lb": 1, "lbu": 1, "lh": 2, "lhu": 2, "lw": 4}
STORES = {"sb": 1, "sh": 2, "sw": 4}


def memory_operand(rng, size):
    """Base s0 = 0x1000_0000 or s1 = 0x1000_0800; both reach the same 4 KB window."""
    if rng.random() < 0.5:
        offset = rng.randrange(0, 64, size)              # a hot spot: stores then loads hit the same words
        return f"{offset}(s0)"
    offset = rng.randrange(-2048, 2048, size)
    return f"{offset}(s1)"


def straight_line(rng):
    """One instruction that does not change the control flow."""
    kind = rng.choices(["r", "i", "shift", "upper", "load", "store", "fence"],
                       weights=[25, 20, 8, 5, 20, 20, 2])[0]
    rd = rng.choice(POOL + ["zero"])
    rs1 = rng.choice(POOL + ["zero"])
    rs2 = rng.choice(POOL + ["zero"])
    if kind == "r":
        return f"{rng.choice(R_OPS)} {rd}, {rs1}, {rs2}"
    if kind == "i":
        return f"{rng.choice(I_OPS)} {rd}, {rs1}, {rng.randint(-2048, 2047)}"
    if kind == "shift":
        return f"{rng.choice(SHIFT_OPS)} {rd}, {rs1}, {rng.randint(0, 31)}"
    if kind == "upper":
        return f"{rng.choice(['lui', 'auipc'])} {rd}, {rng.randint(0, 0xFFFFF)}"
    if kind == "load":
        op = rng.choice(list(LOADS))
        return f"{op} {rd}, {memory_operand(rng, LOADS[op])}"
    if kind == "store":
        op = rng.choice(list(STORES))
        return f"{op} {rs2}, {memory_operand(rng, STORES[op])}"
    return "fence.i"


def generate(seed, length=400):
    rng = random.Random(seed)
    lines = [f"# random program, seed {seed}",
             "        lui   s0, 0x10000",
             "        li    s1, 0x10000800"]
    for register in POOL:
        lines.append(f"        li    {register}, {rng.randint(-2**31, 2**31 - 1)}")

    label_count = 0
    emitted = 0
    while emitted < length:
        choice = rng.random()
        if choice < 0.12:                                 # forward branch over 1-3 instructions
            label = f"skip{label_count}"
            label_count += 1
            op = rng.choice(BRANCHES)
            lines.append(f"        {op} {rng.choice(POOL)}, {rng.choice(POOL + ['zero'])}, {label}")
            for _ in range(rng.randint(1, 3)):
                lines.append(f"        {straight_line(rng)}")
            lines.append(f"{label}:")
            emitted += 4
        elif choice < 0.15:                               # JAL over 1-2 instructions
            label = f"skip{label_count}"
            label_count += 1
            lines.append(f"        jal   {rng.choice(POOL + ['zero'])}, {label}")
            for _ in range(rng.randint(1, 2)):
                lines.append(f"        {straight_line(rng)}")
            lines.append(f"{label}:")
            emitted += 3
        elif choice < 0.17:                               # JALR over 1 instruction
            lines.append("        auipc t6, 0")
            lines.append(f"        jalr  {rng.choice(POOL + ['zero'])}, 12(t6)")
            lines.append(f"        {straight_line(rng)}")
            emitted += 3
        else:
            lines.append(f"        {straight_line(rng)}")
            emitted += 1
    lines.append("end:    j     end")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    print(generate(int(sys.argv[1])), end="")
