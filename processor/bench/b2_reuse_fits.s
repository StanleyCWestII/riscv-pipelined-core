# B2 - temporal locality, working set FITS in the cache.
# Four passes over 16 words (0x000..0x03F = 4 blocks). The cache holds 16
# blocks, so nothing is ever evicted and only the first pass pays.
#
# Expected: 64 accesses, 4 misses (compulsory only), 93.8% hit.
addi x20, x0, 4             # pass count
addi x21, x0, -1
addi x13, x0, 4
addi x11, x0, 0             # sum
outer:
addi x10, x0, 0             # ptr = 0x000
addi x12, x0, 64            # end = 0x040, 16 words
inner:
lw   x5, 0(x10)
add  x11, x11, x5
add  x10, x10, x13
sub  x14, x10, x12
beq  x14, x0, next
beq  x0, x0, inner
next:
add  x20, x20, x21
beq  x20, x0, done
beq  x0, x0, outer
done: beq x0, x0, done
