module top(input logic CLK100MHZ, UART_TXD_IN, output logic UART_RXD_OUT);

logic Valid, Busy;
logic [7:0] Data;

uartecho tx_unit(.clk(CLK100MHZ), .Input({1'b1, Data, 1'b0}), .Send(Valid), .Busy(Busy), .tx(UART_RXD_OUT));
receiver rx_unit(.clk(CLK100MHZ), .rx(UART_TXD_IN), .Valid(Valid), .Data(Data));
pipelined processor(.clk(CLK100MHZ), .RxData(Data), .RxValid(Valid), .TxBusy(Busy));

endmodule
