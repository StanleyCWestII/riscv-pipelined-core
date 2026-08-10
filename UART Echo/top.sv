module top(input logic Reset, CLK100MHZ, UART_TXD_IN, output logic UART_RXD_OUT);

logic Valid, Busy, TxSend;
logic [7:0] Data, TxByte;

uartecho tx_unit(.clk(CLK100MHZ), .Input({1'b1, TxByte, 1'b0}), .Send(TxSend), .Busy(Busy), .tx(UART_RXD_OUT));
receiver rx_unit(.clk(CLK100MHZ), .rx(UART_TXD_IN), .Valid(Valid), .Data(Data));
pipelined processor(.reset(Reset), .clk(CLK100MHZ), .TxSend(TxSend), .TxByte(TxByte), .RxData(Data), .RxValid(Valid), .TxBusy(Busy));

endmodule
