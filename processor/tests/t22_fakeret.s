# T22: a jalr that looks like a return but has no matching jal.
# x1 is set by addi, so the return stack holds nothing useful. The first
# execution is a BTB miss and marks the row as a return. The second execution
# hits, reads the stack (garbage), and the E-stage target compare must catch
# it and redirect to the real x1. Without the check this program loops forever.
    addi x5, x0, 0          # 0x00
    addi x1, x0, 0x1c       # 0x04  first target
again:
    jalr x0, 0(x1)          # 0x08  run 1 -> 0x1c (miss), run 2 -> 0x28 (stack says 0)
    addi x6, x0, 66         # 0x0c  never
    addi x7, x0, 77         # 0x10  never
    addi x8, x0, 88         # 0x14  never
    addi x0, x0, 0          # 0x18  never
    addi x5, x5, 1          # 0x1c  x5 = 1
    addi x1, x0, 0x28       # 0x20  second target
    jal  x0, again          # 0x24  back to the same jalr, x0 so no push
    addi x5, x5, 10         # 0x28  x5 = 11 only if the mispredicted return was caught
done: beq x0, x0, done      # 0x2c
