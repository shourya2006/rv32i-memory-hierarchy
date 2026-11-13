# Block copy: fill a 4 KB source with src[i] = 5i, copy it to a 4 KB
# destination, then add up the destination. All loops are unrolled 4x, so
# about half of all instructions are loads or stores, and the data streams
# straight through any cache (every line is used once, then evicted dirty).
# Prints: the sum of the destination.

        .data
src:    .space 4096
dst:    .space 4096

        .text
        lui   s11, 0x20000           # output port
        la    s0, src
        la    s2, dst
        li    s1, 1024               # words

        li    t0, 0                  # value of src[i]
        mv    t3, s0
        li    t2, 5120               # 5 * 1024
fill:   sw    t0, 0(t3)
        addi  t1, t0, 5
        sw    t1, 4(t3)
        addi  t1, t0, 10
        sw    t1, 8(t3)
        addi  t1, t0, 15
        sw    t1, 12(t3)
        addi  t0, t0, 20
        addi  t3, t3, 16
        bne   t0, t2, fill

        mv    t3, s0                 # read pointer
        mv    t5, s2                 # write pointer
        mv    t6, s2                 # end of src = start of dst
copy:   lw    a1, 0(t3)
        lw    a2, 4(t3)
        lw    a3, 8(t3)
        lw    a4, 12(t3)
        sw    a1, 0(t5)
        sw    a2, 4(t5)
        sw    a3, 8(t5)
        sw    a4, 12(t5)
        addi  t3, t3, 16
        addi  t5, t5, 16
        bne   t3, t6, copy

        li    a0, 0
        mv    t5, s2
        li    t6, 4096
        add   t6, s2, t6             # end of dst
check:  lw    a1, 0(t5)
        lw    a2, 4(t5)
        lw    a3, 8(t5)
        lw    a4, 12(t5)
        add   a0, a0, a1
        add   a0, a0, a2
        add   a0, a0, a3
        add   a0, a0, a4
        addi  t5, t5, 16
        bne   t5, t6, check
        sw    a0, 0(s11)
end:    j     end
