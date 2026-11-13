# Collatz: total number of steps to reach 1 for every n from 1 to 200.
# Registers only, branch-heavy: the data side is idle, so this shows what
# each memory organisation costs when only instruction fetch matters.
# Prints: the total number of steps.

        lui   s11, 0x20000           # output port
        li    a0, 0                  # total steps
        li    s0, 1                  # n
        li    s1, 201
        li    s2, 1
outer:  mv    t0, s0
inner:  beq   t0, s2, next_n
        andi  t2, t0, 1
        beqz  t2, even
        slli  t3, t0, 1              # odd: 3n + 1
        add   t0, t0, t3
        addi  t0, t0, 1
        j     counted
even:   srli  t0, t0, 1
counted:
        addi  a0, a0, 1
        j     inner
next_n: addi  s0, s0, 1
        bne   s0, s1, outer
        sw    a0, 0(s11)
end:    j     end
