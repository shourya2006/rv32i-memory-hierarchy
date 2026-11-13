# Quicksort: sort 256 pseudo-random words with a recursive quicksort
# (Lomuto partition). Each call keeps its return address and saved
# registers on the stack in data memory.
# Prints: sum of the array, number of out-of-order neighbours (0 when
# sorted), smallest value, largest value.

        .data
array:  .space 1024                  # 256 words

        .text
        li    sp, 0x10004000         # stack grows down from the top of data memory
        lui   s11, 0x20000           # output port

        # fill with xorshift32 numbers, shifted down to 24 bits
        la    s0, array
        li    s1, 256
        li    t0, 0x12345678         # seed
        mv    t1, s0
        li    t2, 0
fill:   slli  t3, t0, 13
        xor   t0, t0, t3
        srli  t3, t0, 17
        xor   t0, t0, t3
        slli  t3, t0, 5
        xor   t0, t0, t3
        srli  t4, t0, 8
        sw    t4, 0(t1)
        addi  t1, t1, 4
        addi  t2, t2, 1
        bne   t2, s1, fill

        mv    a0, s0                 # qsort(array, 0, 255)
        li    a1, 0
        li    a2, 255
        call  qsort

        li    a0, 0                  # sum
        li    a1, 0                  # out-of-order neighbours
        mv    t1, s0
        lw    t3, 0(t1)
        add   a0, a0, t3
        li    t2, 1
check:  lw    t4, 4(t1)
        add   a0, a0, t4
        bge   t4, t3, ordered
        addi  a1, a1, 1
ordered:
        mv    t3, t4
        addi  t1, t1, 4
        addi  t2, t2, 1
        bne   t2, s1, check
        sw    a0, 0(s11)
        sw    a1, 0(s11)
        lw    t0, 0(s0)
        sw    t0, 0(s11)
        lw    t0, 1020(s0)
        sw    t0, 0(s11)
end:    j     end

# qsort(a0 = base, a1 = lo, a2 = hi): sort base[lo..hi], both ends included
qsort:  bge   a1, a2, qs_return      # zero or one element
        addi  sp, sp, -32
        sw    ra, 28(sp)
        sw    s0, 24(sp)
        sw    s1, 20(sp)
        sw    s2, 16(sp)
        sw    s3, 12(sp)
        mv    s0, a0
        mv    s1, a1
        mv    s2, a2

        slli  t0, s2, 2              # pivot = base[hi]
        add   t0, s0, t0
        lw    t1, 0(t0)
        addi  t2, s1, -1             # i = lo - 1
        mv    t3, s1                 # j = lo
part:   bge   t3, s2, part_done
        slli  t4, t3, 2
        add   t4, s0, t4
        lw    t5, 0(t4)              # base[j]
        bgt   t5, t1, part_next      # larger than the pivot: stays on the right
        addi  t2, t2, 1
        slli  t6, t2, 2
        add   t6, s0, t6
        lw    a3, 0(t6)              # swap base[i], base[j]
        sw    t5, 0(t6)
        sw    a3, 0(t4)
part_next:
        addi  t3, t3, 1
        j     part
part_done:
        addi  t2, t2, 1              # the pivot goes to i + 1
        slli  t6, t2, 2
        add   t6, s0, t6
        lw    a3, 0(t6)
        sw    t1, 0(t6)
        sw    a3, 0(t0)
        mv    s3, t2

        mv    a0, s0                 # qsort(base, lo, p - 1)
        mv    a1, s1
        addi  a2, s3, -1
        call  qsort
        mv    a0, s0                 # qsort(base, p + 1, hi)
        addi  a1, s3, 1
        mv    a2, s2
        call  qsort

        lw    ra, 28(sp)
        lw    s0, 24(sp)
        lw    s1, 20(sp)
        lw    s2, 16(sp)
        lw    s3, 12(sp)
        addi  sp, sp, 32
qs_return:
        ret
