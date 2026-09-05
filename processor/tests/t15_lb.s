# T15: signed byte loads from every byte lane.
# 0x80FF7F01 in little-endian memory gives bytes 01, 7F, FF, 80.
    lui x1, 0x80FF8
    addi x1, x1, -255        # x1 = 0x80FF7F01
    sw x1, 0(x0)             # write-through store, no write allocation

    lb x2, 0(x0)             # cold miss, byte lane 0:  1
    lb x3, 1(x0)             # cache hit, byte lane 1: 127
    lb x4, 2(x0)             # cache hit, byte lane 2:  -1
    lb x5, 3(x0)             # cache hit, byte lane 3: -128
    lbu x13, 0(x0)           # zero-extended lane 0: 1
    lbu x14, 1(x0)           # zero-extended lane 1: 127
    lbu x15, 2(x0)           # zero-extended lane 2: 255
    lbu x16, 3(x0)           # zero-extended lane 3: 128

    addi x6, x0, 2
    lb x7, -2(x6)            # nonzero base and negative offset: 1
    lb x8, 1(x6)             # nonzero base and positive offset: -128

    lb x9, 2(x0)
    addi x10, x9, 1          # immediate load-use dependency: -1 + 1 = 0

    addi x11, x0, 1
    lb x12, 0(x11)           # base forwarded from preceding instruction: 127

done: beq x0, x0, done
