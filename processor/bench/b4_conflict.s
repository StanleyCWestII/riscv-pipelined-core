# B4 - conflict misses. Three words, 12 bytes of live data.
# 0x000, 0x200 and 0x400 all have set bits [8:6] = 000 and tags [15:9] = 0, 1, 2.
# They compete for one set. A 2-way set holds two of them; the third evicts
# the least recently used, which is exactly the one needed next, so under LRU
# every single access misses. A 4-way set holds all three.
#
# Expected direct-mapped: 96 accesses, 96 misses,  0.0% hit.
# Expected 2-way LRU:     96 accesses, 96 misses,  0.0% hit.
# Expected 4-way:         96 accesses,  3 misses, 96.9% hit.
addi x10, x0, 0             # A = 0x000  -> set 0, tag 0
addi x11, x0, 512           # B = 0x200  -> set 0, tag 1
addi x12, x0, 1024          # C = 0x400  -> set 0, tag 2
addi x20, x0, 32
addi x21, x0, -1
loop:
lw   x5, 0(x10)
lw   x6, 0(x11)
lw   x7, 0(x12)
add  x20, x20, x21
beq  x20, x0, done
beq  x0, x0, loop
done: beq x0, x0, done
