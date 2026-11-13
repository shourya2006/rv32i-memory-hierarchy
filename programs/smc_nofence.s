# Self-modifying code without FENCE.I: the same as smc_test.s, minus the
# fence. This is a software bug on purpose, to show the incoherence.
#   von Neumann, unified cache   prints 1, 2  (one memory: the new code is seen)
#   split L1 caches              prints 1, 1  (the new instruction sits dirty in
#                                              the D-cache; the I-cache still
#                                              holds the old line)
#   Harvard                      bus error

        lui   s11, 0x20000           # output port
        li    sp, 0x10004000
        call  patch_me
        sw    a0, 0(s11)
        la    t0, patch_me
        li    t1, 0x00200513         # machine code of "li a0, 2"
        sw    t1, 0(t0)
        call  patch_me
        sw    a0, 0(s11)
end:    j     end

patch_me:
        li    a0, 1
        ret
