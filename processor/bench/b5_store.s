# B5 - sequential STORE stream, the write-side twin of B1.
# Writes 256 consecutive words (0x000..0x3FF = 16 lines) exactly once, 16
# stores per line. With write-allocate the first store to each line misses
# and drags the line in; the next 15 stores hit.
#
# Cache: 8 sets x 4 ways x 16 words = 32 lines of 64 B = 2 KiB.
# Expected: 256 accesses, 16 misses, 93.8% hit, same shape as B1.
# The number that separates write policies is the "mem wr" column:
#   write-through: 256 DataMem writes (one per store)
#   write-back:     16 DataMem writes at most (one per dirty line evicted,
#                   0 if nothing is ever evicted)
addi x10, x0, 0             # ptr  = 0x000
addi x12, x0, 1024          # end  = 0x400
addi x13, x0, 4             # stride = one word
addi x11, x0, 0             # value to store, changes every iteration
loop:
sw   x11, 0(x10)
add  x11, x11, x13
add  x10, x10, x13
sub  x14, x10, x12
beq  x14, x0, done
beq  x0, x0, loop
done: beq x0, x0, done
