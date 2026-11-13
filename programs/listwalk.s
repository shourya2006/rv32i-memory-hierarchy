# Linked-list walk: 512 nodes of 8 bytes (next, value) = 4 KB, placed in a
# scattered order (node k sits in slot (181 * k) mod 512), then walked four
# times. Each step loads the next pointer and immediately uses it, so this
# is the worst case for latency: no locality and a load-use chain.
# Prints: the sum of every value seen.

        .data
nodes:  .space 4096

        .text
        lui   s11, 0x20000           # output port
        la    s0, nodes
        li    s1, 512

        li    t0, 0                  # k
        li    t1, 0                  # slot of node k
build:  slli  t2, t1, 3
        add   t2, s0, t2             # address of node k
        addi  t3, t1, 181
        andi  t3, t3, 511            # slot of node k + 1
        slli  t4, t3, 3
        add   t4, s0, t4             # address of node k + 1
        addi  t5, t0, 1
        bne   t5, s1, link
        li    t4, 0                  # the last node ends the list
link:   sw    t4, 0(t2)
        xori  t6, t0, 0x55
        sw    t6, 4(t2)
        mv    t1, t3
        mv    t0, t5
        bne   t0, s1, build

        li    a0, 0
        li    s2, 4                  # passes
walk:   mv    t0, s0                 # node 0 is in slot 0
step:   lw    t1, 4(t0)
        add   a0, a0, t1
        lw    t0, 0(t0)
        bnez  t0, step
        addi  s2, s2, -1
        bnez  s2, walk
        sw    a0, 0(s11)
end:    j     end
