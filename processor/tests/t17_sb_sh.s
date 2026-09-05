# T17: byte and halfword stores.
# The initial word is AABBCCDD, stored little-endian as DD CC BB AA.
    lui x1, 0xAABBD
    addi x1, x1, -803         # x1 = 0xAABBCCDD
    sw x1, 0(x0)

    lw x6, 0(x0)              # allocate the cache line

    addi x2, x0, 0x11
    addi x3, x0, 0x22
    addi x4, x0, 0x33
    addi x5, x0, 0x44
    sb x2, 0(x0)
    sb x3, 1(x0)
    sb x4, 2(x0)
    sb x5, 3(x0)

    lui x7, 0x6
    addi x7, x7, 1621        # x7 = 0x00006655
    sh x7, 0(x0)
    sh x7, 1(x0)
    sh x7, 2(x0)

done: beq x0, x0, done
