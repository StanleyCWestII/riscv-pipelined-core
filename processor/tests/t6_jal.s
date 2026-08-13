# T6: jal link value and squash of the two instructions behind it
addi x1, x0, 1
jal  x2, sub1               # x2 = 4 + 4 = 8
addi x30, x0, 111           # squashed
addi x31, x0, 222           # squashed
sub1:
add  x3, x2, x0             # use the link register IMMEDIATELY at the target.
                            # jal writes PCPlus4, not an ALU result, so this
                            # must forward from W, never from ALUResultM.
addi x5, x2, 4              # link + 4, still close behind the jal
jal  x0, sub2               # link discarded into x0
addi x29, x0, 333           # squashed
sub2:
addi x4, x0, 8
done: beq x0, x0, done
