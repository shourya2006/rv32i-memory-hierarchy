# Self-checking instruction test. Each check puts its number in gp,
# computes a result into t0 and compares it with the expected value in t1.
# Prints 0x600d when every check passes, or the number of the failed check.

        lui   s0, 0x10000        # data memory
        lui   s1, 0x20000        # output port
        li    a0, 5
        li    a1, -3

# ---- register-register ALU ----
        li    gp, 1
        add   t0, a0, a1
        li    t1, 2
        bne   t0, t1, fail
        li    gp, 2
        sub   t0, a0, a1
        li    t1, 8
        bne   t0, t1, fail
        li    gp, 3
        and   t0, a0, a1
        li    t1, 5
        bne   t0, t1, fail
        li    gp, 4
        or    t0, a0, a1
        li    t1, -3
        bne   t0, t1, fail
        li    gp, 5
        xor   t0, a0, a1
        li    t1, -8
        bne   t0, t1, fail
        li    gp, 6
        slt   t0, a1, a0         # -3 < 5 signed
        li    t1, 1
        bne   t0, t1, fail
        li    gp, 7
        sltu  t0, a1, a0         # 0xfffffffd < 5 unsigned is false
        bnez  t0, fail
        li    gp, 8
        li    a2, 3
        sll   t0, a0, a2
        li    t1, 40
        bne   t0, t1, fail
        li    gp, 9
        li    a3, 28
        srl   t0, a1, a3
        li    t1, 15
        bne   t0, t1, fail
        li    gp, 10
        li    a2, 1
        sra   t0, a1, a2
        li    t1, -2
        bne   t0, t1, fail

# ---- register-immediate ALU and upper immediates ----
        li    gp, 11
        addi  t0, a0, -10
        li    t1, -5
        bne   t0, t1, fail
        li    gp, 12
        slti  t0, a1, -2
        li    t1, 1
        bne   t0, t1, fail
        li    gp, 13
        sltiu t0, a0, -1         # 5 < 0xffffffff unsigned
        li    t1, 1
        bne   t0, t1, fail
        li    gp, 14
        xori  t0, a0, 0xff
        li    t1, 250
        bne   t0, t1, fail
        li    gp, 15
        ori   t0, a0, 0x700
        li    t1, 0x705
        bne   t0, t1, fail
        li    gp, 16
        andi  t0, a1, 0xf0
        li    t1, 0xf0
        bne   t0, t1, fail
        li    gp, 17
        slli  t0, a0, 4
        li    t1, 80
        bne   t0, t1, fail
        li    gp, 18
        srli  t0, a1, 30
        li    t1, 3
        bne   t0, t1, fail
        li    gp, 19
        srai  t0, a1, 30
        li    t1, -1
        bne   t0, t1, fail
        li    gp, 20
        lui   t0, 0x12345
        srli  t0, t0, 12
        li    t1, 0x12345
        bne   t0, t1, fail
        li    gp, 21
        auipc t0, 1              # pc + 4096
        auipc t1, 0              # pc of this line = previous pc + 4
        sub   t0, t0, t1
        li    t1, 4092
        bne   t0, t1, fail

# ---- loads and stores (through rw_control) ----
        li    t2, 0x8091a2b3
        sw    t2, 0(s0)
        li    gp, 22
        lw    t0, 0(s0)
        bne   t0, t2, fail
        li    gp, 23
        lb    t0, 0(s0)
        li    t1, -77            # 0xb3
        bne   t0, t1, fail
        li    gp, 24
        lbu   t0, 0(s0)
        li    t1, 0xb3
        bne   t0, t1, fail
        li    gp, 25
        lb    t0, 1(s0)
        li    t1, -94            # 0xa2
        bne   t0, t1, fail
        li    gp, 26
        lb    t0, 3(s0)
        li    t1, -128           # 0x80
        bne   t0, t1, fail
        li    gp, 27
        lh    t0, 2(s0)
        li    t1, -32623         # 0x8091
        bne   t0, t1, fail
        li    gp, 28
        lhu   t0, 2(s0)
        li    t1, 0x8091
        bne   t0, t1, fail
        li    gp, 29
        lh    t0, 0(s0)
        li    t1, -23885         # 0xa2b3
        bne   t0, t1, fail
        li    gp, 30
        li    t3, 0x55
        sb    t3, 1(s0)
        lw    t0, 0(s0)
        li    t1, 0x809155b3
        bne   t0, t1, fail
        li    gp, 31
        li    t3, 0x1234
        sh    t3, 2(s0)
        lw    t0, 0(s0)
        li    t1, 0x123455b3
        bne   t0, t1, fail

# ---- branches: one not-taken and one taken case each ----
        li    gp, 32
        beq   a0, a1, fail
        beq   a0, a0, ok32
        j     fail
ok32:   li    gp, 33
        bne   a0, a0, fail
        bne   a0, a1, ok33
        j     fail
ok33:   li    gp, 34
        blt   a0, a1, fail
        blt   a1, a0, ok34
        j     fail
ok34:   li    gp, 35
        bge   a1, a0, fail
        bge   a0, a0, ok35
        j     fail
ok35:   li    gp, 36
        bltu  a1, a0, fail
        bltu  a0, a1, ok36
        j     fail
ok36:   li    gp, 37
        bgeu  a0, a1, fail
        bgeu  a1, a0, ok37
        j     fail

# ---- jumps and the link register ----
ok37:   li    gp, 38
        auipc t1, 0              # t1 = pc of this line
        jal   ra, ok38           # ra = t1 + 8
        j     fail
ok38:   addi  t1, t1, 8
        bne   ra, t1, fail
        li    gp, 39
        auipc t0, 0              # t0 = pc of this line
        jalr  ra, 12(t0)         # jump to t0 + 12, ra = t0 + 8
        j     fail
        addi  t1, t0, 8
        bne   ra, t1, fail

# ---- x0 stays zero ----
        li    gp, 40
        addi  zero, a0, 0
        bnez  zero, fail

        li    t0, 0x600d
        sw    t0, 0(s1)
pass:   j     pass

fail:   sw    gp, 0(s1)
fail_end:
        j     fail_end
