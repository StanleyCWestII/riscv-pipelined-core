# T14: register-indirect jumps. Addresses are byte addresses, fixed below.
# Wrong-path stores and register writes must be squashed.
# AUIPC at the first target detects an odd PC even though ROM drops bits [1:0].
    addi x5, x0, 25          # 0x00: odd target, immediate M forwarding
    jalr x1, 0(x5)          # 0x04: link 8, target 24
    sw x5, 4(x0)            # squashed
    addi x30, x0, 1         # squashed
    nop
    nop
    auipc x2, 0             # 0x18: must observe 24, not 25
    addi x5, x0, 52         # 0x1c
    nop
    jalr x3, -4(x5)         # 0x24: W forwarding, negative offset, target 48
    sw x5, 4(x0)            # squashed
    addi x30, x0, 2         # squashed
    addi x4, x3, 0          # 0x30: consume link immediately at target
    addi x6, x0, 76         # 0x34
    jalr x6, 0(x6)          # 0x38: rd == rs1, use old base; link 60
    sw x6, 4(x0)            # squashed
    addi x30, x0, 3         # squashed
    nop
    nop
    addi x7, x6, 0          # 0x4c: consume overwritten base as return address
    addi x8, x0, 104        # 0x50
    sw x8, 0(x0)
    lw x9, 0(x0)            # cold cache miss plus load-use dependency
    jalr x10, 0(x9)         # 0x5c: target 104, link 96
    sw x9, 4(x0)            # squashed
    addi x30, x0, 4         # squashed
    addi x11, x10, 0        # 0x68: consume link
    lw x12, 0(x0)           # warm cache hit plus load-use dependency
    jalr x13, 20(x12)       # 0x70: target 124, link 116
    sw x12, 4(x0)           # squashed
    addi x30, x0, 5         # squashed
    addi x14, x13, 0        # 0x7c
    jalr x0, 140(x0)        # 0x80: zero base, discard link, positive offset
    sw x14, 4(x0)           # squashed
    addi x30, x0, 6         # squashed
    addi x15, x0, 7         # 0x8c: x0 must still read zero
done: beq x0, x0, done
