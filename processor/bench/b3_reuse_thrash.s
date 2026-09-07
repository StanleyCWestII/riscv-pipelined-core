# B3 - same reuse pattern as B2, working set EXCEEDS the cache.
# Four passes over 1024 words (0x000..0xFFF = 64 lines) into a 16-line cache.
# By the time a pass wraps around, every line it wants has been evicted by the
# same pass, so the reuse buys nothing and each pass re-misses every line.
# 4 KiB working set stays out of reach of a 4-way (2 KiB) upgrade too.
#
# Expected: 4096 accesses, 256 misses, 93.8% hit -- identical to B1 despite
# four times the reuse. That gap against B2 is the capacity miss.
addi x20, x0, 4
addi x21, x0, -1
addi x13, x0, 4
addi x11, x0, 0
addi x12, x0, 1024
slli x12, x12, 2            # end = 0x1000, 1024 words (too big for one addi)
outer:
addi x10, x0, 0             # ptr = 0x000
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
