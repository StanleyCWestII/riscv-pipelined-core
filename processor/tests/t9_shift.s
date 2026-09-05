# T9: shifts and xor.
# Targets the four ways a shift implementation usually breaks:
#   - >>> on an unsigned operand silently becoming a logical shift
#   - shift amount not masked to 5 bits
#   - slli/srli/srai treated as a 12-bit signed immediate instead of a shamt
#   - srl and sra swapped

    addi x1,  x0, 12            # 0x0000000C
    addi x2,  x0, 10            # 0x0000000A
    addi x3,  x0, -1            # 0xFFFFFFFF
    addi x4,  x0, 4             # shift amount
    addi x5,  x0, 36            # 36 & 0x1F == 4, exercises the mask
    addi x17, x0, -128          # 0xFFFFFF80

# ---- xor -------------------------------------------------------------
    xor  x6,  x1, x2            # 0xC ^ 0xA = 6
    xor  x7,  x1, x1            # a ^ a = 0
    xori x8,  x1, -1            # NOT 12 -> 0xFFFFFFF3, needs sign-extended imm
    xori x9,  x1, 10            # 6

# ---- sll -------------------------------------------------------------
    sll  x10, x1, x4            # 12 << 4  = 192
    sll  x11, x1, x5            # shift by 36 must behave as shift by 4
    slli x12, x1, 4             # 192
    sll  x21, x1, x0            # shift by 0 is identity

# ---- srl: zero fill --------------------------------------------------
    srl  x13, x3, x4            # 0xFFFFFFFF >> 4 = 0x0FFFFFFF
    srli x14, x3, 4             # 0x0FFFFFFF
    srl  x19, x17, x4           # 0xFFFFFF80 >> 4 = 0x0FFFFFF8

# ---- sra: sign fill --------------------------------------------------
    sra  x15, x3, x4            # -1 >> 4 stays -1
    srai x16, x3, 4             # -1
    sra  x18, x17, x4           # -128 >> 4 = -8
    srai x20, x17, 4            # -8; catches funct7 bleeding into the immediate
