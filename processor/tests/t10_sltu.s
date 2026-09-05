# T10: unsigned comparison.
# The whole point of sltu is that the SAME bits give a different answer than
# slt. x1 is 0xFFFFFFFF, which is -1 signed and 4294967295 unsigned, so every
# pair below separates a correct sltu from one that quietly does a signed
# compare.

    addi x1, x0, -1             # 0xFFFFFFFF
    addi x2, x0, 1
    addi x3, x0, 12
    addi x4, x0, 10

# ---- the discriminator ----------------------------------------------
    slt   x5,  x1, x2           # signed:    -1 < 1            -> 1
    sltu  x6,  x1, x2           # unsigned:  4294967295 < 1    -> 0
    sltu  x7,  x2, x1           # unsigned:  1 < 4294967295    -> 1

# ---- ordinary small values, both orders and equality -----------------
    sltu  x8,  x1, x1           # equal is not less than       -> 0
    sltu  x9,  x4, x3           # 10 < 12                      -> 1
    sltu  x10, x3, x4           # 12 < 10                      -> 0

# ---- immediate forms -------------------------------------------------
    sltiu x11, x2, 5            # 1 < 5                        -> 1
    sltiu x12, x1, 5            # 4294967295 < 5               -> 0
    slti  x13, x1, 5            # signed contrast: -1 < 5      -> 1
    sltiu x14, x0, 1            # 0 < 1, the seqz idiom        -> 1
    sltiu x15, x2, -1           # imm sign-extends to 0xFFFFFFFF,
                                # then compares unsigned: 1 < huge -> 1
