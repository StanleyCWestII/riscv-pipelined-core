# T12: lui.
#
# The important case is x5. In a lui instruction, bits [19:15] are part of the
# immediate, not a register number. For `lui x5, 0x12345` those bits happen to
# spell x8. If the datapath adds rs1 to the immediate, the result comes out as
# 0x12345111 instead of 0x12345000, so x8 is deliberately loaded first and given
# time to reach the register file.

    addi x8, x0, 273            # 0x111, sits in the rs1 field of the luis below
    nop
    nop
    nop                         # let x8 commit; lui does not read rs1, so it
                                # is not forwarded

    lui  x5, 0x12345            # 0x12345000, must NOT be 0x12345111

    lui  x1, 0x00001            # smallest nonzero
    lui  x2, 0xFFFFF            # all ones: must not sign-extend anywhere
    lui  x3, 0x00000            # zero

    lui  x4, 0x12345            # the standard pair: build a full 32-bit constant
    addi x4, x4, 0x678          # 0x12345678

    lui  x6, 0xABCDE            # result must forward into the next instruction
    addi x7, x6, 0              # 0xABCDE000
