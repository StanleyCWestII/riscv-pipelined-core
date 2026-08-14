# B3 - same reuse pattern, working set EXCEEDS the cache.
# Four passes over 128 words (0x000..0x1FF = 32 blocks) into a 16-block cache.
# By the time a pass wraps around, every line it wants has been evicted by the
# same pass, so the reuse buys nothing and each pass re-misses every block.
#
# Expected: 512 accesses, 128 misses, 75.0% hit -- identical to B1 despite
# four times the reuse. That gap against B2 is the capacity miss.
addi x20, x0, 4
addi x21, x0, -1
addi x13, x0, 4
addi x11, x0, 0
outer:
addi x10, x0, 0             # ptr = 0x000
addi x12, x0, 512           # end = 0x200, 128 words
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
