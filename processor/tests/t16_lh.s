# T16: aligned signed and unsigned halfword loads.
# Memory word 0x80FF7F01 is little endian: low half 0x7F01, high half 0x80FF.
    lui x1, 0x80FF8
    addi x1, x1, -255
    sw x1, 0(x0)

    lh  x2, 0(x0)             # cold miss, low half, positive
    lhu x3, 0(x0)             # hit, low half, zero extension
    lh  x4, 2(x0)             # hit, high half, sign extension
    lhu x5, 2(x0)             # hit, high half, zero extension

    addi x6, x0, 2
    lh  x7, -2(x6)             # nonzero base and negative offset
    lhu x8, 0(x6)              # nonzero base, high half, unsigned
    lh  x9, 2(x0)
    addi x10, x9, 1            # load-use dependency: 0xFFFF80FF + 1

done: beq x0, x0, done
