# Self-modifying code, done correctly: call patch_me (returns 1), overwrite
# its first instruction with "li a0, 2", execute FENCE.I, call it again.
#   von Neumann, unified cache   prints 1, 2  (one memory, always coherent)
#   split L1 caches              prints 1, 2  (FENCE.I writes back the D-cache
#                                              and empties the I-cache)
#   Harvard                      bus error    (the data side cannot write code)

        lui   s11, 0x20000           # output port
        li    sp, 0x10004000
        call  patch_me
        sw    a0, 0(s11)
        la    t0, patch_me
        li    t1, 0x00200513         # machine code of "li a0, 2"
        sw    t1, 0(t0)
        fence.i
        call  patch_me
        sw    a0, 0(s11)
end:    j     end

patch_me:
        li    a0, 1
        ret
