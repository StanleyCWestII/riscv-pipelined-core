module top(input logic CLK100MHZ, Button, UART_TXD_IN, output logic UART_RXD_OUT);

logic Valid;
logic [7:0] Data;

uartecho tx_unit(.clk(CLK100MHZ), .Input({1'b1, Data, 1'b0}), .Send(Valid), .tx(UART_RXD_OUT));
receiver rx_unit(.clk(CLK100MHZ), .rx(UART_TXD_IN), .Valid(Valid), .Data(Data));

endmodule
