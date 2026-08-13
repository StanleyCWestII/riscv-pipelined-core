# UART echo. Polls the memory mapped UART and sends every received byte back.
#
# Memory map, decoded in pipelined.sv from ALUResultM[10] and ALUResultM[3:2]:
#   0x400   store   transmit the low byte of the stored word
#   0x404   load    status: bit 0 = TxBusy, bit 1 = RxReady
#   0x408   load    received byte; the load itself clears RxReady

addi x10, x0, 1024          # x10 = UART base = 0x400

wait_rx:
lw   x5, 4(x10)             # read status
andi x5, x5, 2              # isolate RxReady
beq  x5, x0, wait_rx        # spin while it is clear

lw   x6, 8(x10)             # take the byte; this load clears RxReady

wait_tx:
lw   x5, 4(x10)             # read status again
andi x5, x5, 1              # isolate TxBusy
beq  x5, x0, send           # clear means transmitter is free
beq  x0, x0, wait_tx        # otherwise keep waiting

send:
sw   x6, 0(x10)             # store drives TxSend for one cycle, WDM[7:0] is the byte

beq  x0, x0, wait_rx        # forever
