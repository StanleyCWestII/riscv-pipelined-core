# B4 - conflict misses. Two words, 8 bytes of live data, 0% hit rate.
# 0x000 and 0x100 have the same index bits [7:4] = 0 and different tags
# [9:8] = 00 and 01, so in a direct-mapped cache they have exactly one legal
# slot and it is the same slot. Each access evicts the other.
#
# Expected direct-mapped: 64 accesses, 64 misses, 0.0% hit.
# Expected 2-way:         64 accesses,  2 misses, 96.9% hit.
addi x10, x0, 0             # A = 0x000  -> line 0, tag 00
addi x11, x0, 256           # B = 0x100  -> line 0, tag 01
addi x20, x0, 32
addi x21, x0, -1
loop:
lw   x5, 0(x10)
lw   x6, 0(x11)
add  x20, x20, x21
beq  x20, x0, done
beq  x0, x0, loop
done: beq x0, x0, done
