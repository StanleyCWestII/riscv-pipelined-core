# T13: auipc.  rd = (address of THIS instruction) + (imm << 12)
#
# Addresses are fixed by position, so every expected value below is the
# instruction's own PC plus the shifted immediate. x1 is the discriminator for
# the classic mistake: it sits at 0x14 with a zero immediate, so a design that
# uses PC+4 instead of PC produces 0x18.
#
# x5 repeats the lui rs1 trap: bits [19:15] of `auipc x5, 0x12345` spell x8,
# which is loaded with 0x111 first.

# 0x00
    addi x8, x0, 273            # 0x111
# 0x04
    nop
# 0x08
    nop
# 0x0c
    nop
# 0x10
    auipc x5, 0x12345           # 0x10 + 0x12345000 = 0x12345010
# 0x14
    auipc x1, 0x00000           # 0x14 + 0          = 0x00000014
# 0x18
    auipc x2, 0x00001           # 0x18 + 0x00001000 = 0x00001018
# 0x1c
    auipc x3, 0xFFFFF           # 0x1c + 0xFFFFF000 = 0xFFFFF01C
# 0x20
    auipc x6, 0x00002           # 0x20 + 0x00002000 = 0x00002020
# 0x24
    addi x7, x6, 0              # forwarded out of auipc: 0x00002020
