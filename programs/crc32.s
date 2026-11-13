# CRC-32 (the one used by zip and Ethernet, polynomial 0xEDB88320) over a
# 1 KB buffer, one byte at a time with LBU and eight shift/xor steps per
# byte. Few data accesses per instruction, a tight loop.
# Prints: the CRC, which must equal Python's zlib.crc32 of the same bytes.

        .data
buffer: .space 1024

        .text
        lui   s11, 0x20000           # output port

        la    s0, buffer             # fill with xorshift32 words
        li    s1, 256
        li    t0, 0x2545F491
        mv    t1, s0
fill:   slli  t3, t0, 13
        xor   t0, t0, t3
        srli  t3, t0, 17
        xor   t0, t0, t3
        slli  t3, t0, 5
        xor   t0, t0, t3
        sw    t0, 0(t1)
        addi  t1, t1, 4
        addi  s1, s1, -1
        bnez  s1, fill

        li    a0, -1                 # crc = 0xFFFFFFFF
        li    s2, 0xEDB88320
        mv    t1, s0
        li    s1, 1024
byte:   lbu   t2, 0(t1)
        xor   a0, a0, t2
        li    t3, 8
bit:    andi  t4, a0, 1
        srli  a0, a0, 1
        beqz  t4, no_xor
        xor   a0, a0, s2
no_xor: addi  t3, t3, -1
        bnez  t3, bit
        addi  t1, t1, 1
        addi  s1, s1, -1
        bnez  s1, byte
        not   a0, a0
        sw    a0, 0(s11)
end:    j     end
