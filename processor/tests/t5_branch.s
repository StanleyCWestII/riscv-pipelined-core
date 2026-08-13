# T5: taken and not-taken branches, forwarding into the branch comparison
addi x1, x0, 5
addi x2, x0, 5
addi x3, x0, 9
beq  x1, x2, l1             # TAKEN
addi x30, x0, 111           # squashed
l1:
addi x4, x0, 1
beq  x1, x3, l2             # NOT taken (5 != 9)
addi x5, x0, 2              # must execute
l2:
addi x6, x0, 3
addi x7, x0, 4
beq  x7, x7, l3             # TAKEN, operand forwarded from M (distance 1)
addi x31, x0, 222           # squashed
addi x29, x0, 333           # squashed
l3:
addi x8, x0, 6
done: beq x0, x0, done
