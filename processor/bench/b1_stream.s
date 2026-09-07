# B1 - sequential stream, spatial locality only.
# Walks 256 consecutive words (0x000..0x3FF = 16 lines) exactly once. There is
# no reuse, so every hit comes purely from line size: one miss drags in 15
# future hits.
#
# Cache: 8 sets x 2 ways x 16 words = 16 lines of 64 B = 1 KiB.
# Expected with 16-word lines:  256 accesses,  16 misses, 93.8% hit.
# Expected with 4-word lines:   256 accesses,  64 misses, 75.0% hit.
# Expected with 1-word blocks:  256 accesses, 256 misses,  0.0% hit.
addi x10, x0, 0             # ptr  = 0x000
addi x12, x0, 1024          # end  = 0x400
addi x13, x0, 4             # stride = one word
addi x11, x0, 0             # sum
loop:
lw   x5, 0(x10)
add  x11, x11, x5
add  x10, x10, x13
sub  x14, x10, x12
beq  x14, x0, done
beq  x0, x0, loop
done: beq x0, x0, done
