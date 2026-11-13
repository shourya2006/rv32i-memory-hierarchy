# Matrix multiply: C = A x B for 16 x 16 word matrices (3 KB of data, more
# than one 1 KB data cache). The inner loop walks a row of A and a column
# of B (64-byte stride). RV32I has no multiply instruction, so mul is a
# shift-and-add subroutine.
# Prints: sum of all C entries, C[0][0], C[15][15].

        .data
mat_a:  .space 1024
mat_b:  .space 1024
mat_c:  .space 1024

        .text
        li    sp, 0x10004000
        lui   s11, 0x20000           # output port
        li    s10, 16                # N

        # A[i][j] = (i + 2j) & 15,  B[i][j] = (3i + j) & 15
        la    s0, mat_a
        la    s1, mat_b
        li    t0, 0                  # i
fill_i: li    t1, 0                  # j
fill_j: slli  t2, t1, 1
        add   t2, t2, t0
        andi  t2, t2, 15
        sw    t2, 0(s0)
        slli  t3, t0, 1
        add   t3, t3, t0
        add   t3, t3, t1
        andi  t3, t3, 15
        sw    t3, 0(s1)
        addi  s0, s0, 4
        addi  s1, s1, 4
        addi  t1, t1, 1
        bne   t1, s10, fill_j
        addi  t0, t0, 1
        bne   t0, s10, fill_i

        la    s0, mat_a              # &A[i][0]
        la    s2, mat_c              # &C[i][j]
        li    s3, 0                  # i
mm_i:   li    s4, 0                  # j
mm_j:   li    s5, 0                  # sum
        li    s6, 0                  # k
        mv    s7, s0                 # &A[i][k]
        la    s8, mat_b
        slli  t0, s4, 2
        add   s8, s8, t0             # &B[k][j]
mm_k:   lw    a0, 0(s7)
        lw    a1, 0(s8)
        call  mul
        add   s5, s5, a0
        addi  s7, s7, 4
        addi  s8, s8, 64             # next row of B
        addi  s6, s6, 1
        bne   s6, s10, mm_k
        sw    s5, 0(s2)
        addi  s2, s2, 4
        addi  s4, s4, 1
        bne   s4, s10, mm_j
        addi  s0, s0, 64
        addi  s3, s3, 1
        bne   s3, s10, mm_i

        la    t1, mat_c
        li    t2, 256
        li    a0, 0
total:  lw    t3, 0(t1)
        add   a0, a0, t3
        addi  t1, t1, 4
        addi  t2, t2, -1
        bnez  t2, total
        sw    a0, 0(s11)
        la    t1, mat_c
        lw    t3, 0(t1)
        sw    t3, 0(s11)
        lw    t3, 1020(t1)
        sw    t3, 0(s11)
end:    j     end

# mul: a0 = a0 * a1, by shift and add
mul:    li    t5, 0
mul_loop:
        andi  t6, a1, 1
        beqz  t6, mul_skip
        add   t5, t5, a0
mul_skip:
        slli  a0, a0, 1
        srli  a1, a1, 1
        bnez  a1, mul_loop
        mv    a0, t5
        ret
