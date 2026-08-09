module top(input logic CLK100MHZ, output logic UART_RXD_OUT);

uartecho tx_unit(.clk(CLK100MHZ), .Input(10'b1000100010), .tx(UART_RXD_OUT));

endmodule
