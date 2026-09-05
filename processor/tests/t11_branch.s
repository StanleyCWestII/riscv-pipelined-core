# T11: all six branch conditions, taken and not-taken.
# Every result register starts at 0 (the bench zeroes the file). A taken
# branch skips over the addi, so the register stays 0. A not-taken branch
# falls through and the register becomes 1.
#
#   reg == 0  ->  branch was TAKEN
#   reg == 1  ->  branch was NOT TAKEN

    addi x1, x0, 5
    addi x2, x0, 3
    addi x3, x0, -1             # 0xFFFFFFFF: -1 signed, 4294967295 unsigned
    addi x4, x0, 1
    addi x5, x0, 5              # equal to x1

# ---- beq / bne -------------------------------------------------------
    beq  x1, x5, b1             # 5 == 5, taken
    addi x10, x0, 1
b1: bne  x1, x2, b2             # 5 != 3, taken
    addi x11, x0, 1
b2: bne  x1, x5, b3             # 5 != 5 is false, NOT taken
    addi x21, x0, 1

# ---- blt / bge, signed -----------------------------------------------
b3: blt  x2, x1, b4             # 3 < 5, taken
    addi x12, x0, 1
b4: blt  x1, x2, b5             # 5 < 3 is false, NOT taken
    addi x13, x0, 1
b5: bge  x1, x2, b6             # 5 >= 3, taken.  Catches bge written as <=
    addi x14, x0, 1
b6: bge  x1, x5, b7             # 5 >= 5, taken on equality
    addi x15, x0, 1
b7: bge  x2, x1, b8             # 3 >= 5 is false, NOT taken
    addi x16, x0, 1

# ---- signed vs unsigned on the same bits -----------------------------
b8: blt  x3, x4, b9             # signed:   -1 < 1, taken
    addi x17, x0, 1
b9: bltu x3, x4, b10            # unsigned: 4294967295 < 1 is false, NOT taken
    addi x18, x0, 1
b10: bge x3, x4, b11            # signed:   -1 >= 1 is false, NOT taken
    addi x19, x0, 1
b11: bgeu x3, x4, b12           # unsigned: 4294967295 >= 1, taken
    addi x20, x0, 1
b12:
