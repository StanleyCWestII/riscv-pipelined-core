# T21: call/return pairs. One function, three call sites, plus a nested call.
# Every ret is the same jalr at the same PC but goes to a different address
# each time, which is exactly what a per-PC BTB cannot predict.
    addi x5, x0, 1          # 0x00
    jal  x1, add10          # 0x04  call 1, x1 = 0x08
    addi x6, x5, 0          # 0x08  x6 = 11
    jal  x1, add10          # 0x0c  call 2, x1 = 0x10
    addi x7, x5, 0          # 0x10  x7 = 21
    jal  x1, outer          # 0x14  call 3 (nested), x1 = 0x18
    addi x8, x5, 0          # 0x18  x8 = 131
    addi x9, x0, 9          # 0x1c  runs only if every ret landed
done: beq x0, x0, done      # 0x20
add10:
    addi x5, x5, 10         # 0x24
    jalr x0, 0(x1)          # 0x28  ret
outer:
    addi x2, x1, 0          # 0x2c  save return address, x2 = 0x18
    addi x5, x5, 100        # 0x30
    jal  x1, add10          # 0x34  nested call, x1 = 0x38
    jalr x0, 0(x2)          # 0x38  ret via saved address
