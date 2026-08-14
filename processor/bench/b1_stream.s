# B1 - sequential stream, spatial locality only.
# Walks 64 consecutive words (0x000..0x0FF) exactly once. There is no reuse,
# so every hit comes purely from block size: one miss drags in 3 future hits.
#
# Expected with 16 lines x 4 words:  64 accesses, 16 misses, 75.0% hit.
# Expected with 1-word blocks:       64 accesses, 64 misses,  0.0% hit.
addi x10, x0, 0             # ptr  = 0x000
addi x12, x0, 256           # end  = 0x100
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
