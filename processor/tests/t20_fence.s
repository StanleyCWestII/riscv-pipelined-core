# T20: fence is an in-order no-op on this single-core processor.
    addi x1, x0, 7
    fence
    addi x2, x1, 1
done: beq x0, x0, done
