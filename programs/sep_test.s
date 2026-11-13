# Separation test: load a word from the code region (address 0).
#   Harvard:      the data port cannot reach instruction memory -> bus error.
#   von Neumann:  code and data share one memory -> the load returns the
#                 first instruction word, which is then printed.

        lui   s1, 0x20000        # output port
        lw    t0, 0(zero)
        sw    t0, 0(s1)
end:    j     end
