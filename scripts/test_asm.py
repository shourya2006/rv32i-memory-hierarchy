#!/usr/bin/env python3
"""Checks the assembler against encodings worked out by hand from the
RISC-V specification. Run: python3 scripts/test_asm.py"""

from asm import assemble

CASES = [
    ("addi x1, x0, 5", [0x00500093]),
    ("add x3, x1, x2", [0x002081B3]),
    ("sub x3, x1, x2", [0x402081B3]),
    ("srai x5, x5, 3", [0x4032D293]),
    ("lw x5, 0(x0)", [0x00002283]),
    ("sw x5, 4(x10)", [0x00552223]),
    ("lui x10, 0x10000", [0x10000537]),
    ("jalr x1, 0(x5)", [0x000280E7]),
    ("loop: beq x0, x0, loop", [0x00000063]),
    ("loop: j loop", [0x0000006F]),
    ("loop: nop\nbne x1, x2, loop", [0x00000013, 0xFE209EE3]),
    ("loop: nop\njal ra, loop", [0x00000013, 0xFFDFF0EF]),
    ("li t0, 0x600d", [0x000062B7, 0x00D28293]),
    ("li t0, 0xfff", [0x000012B7, 0xFFF28293]),
    ("call f\nf: ret", [0x004000EF, 0x00008067]),
    ("fence.i", [0x0000100F]),
    ("bgt a0, a1, l\nl: nop", [0x00A5C263, 0x00000013]),
    (".data\nx: .word 5\n.text\nla a0, x", [0x10000537, 0x00050513]),
]


def run():
    for source, expected in CASES:
        words = [word for word, _ in assemble(source)[0]]
        assert words == expected, f"{source!r}: got {[hex(w) for w in words]}, expected {[hex(w) for w in expected]}"


if __name__ == "__main__":
    run()
    print(f"PASS test_asm: {len(CASES)} cases")
