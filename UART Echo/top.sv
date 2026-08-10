module top(input logic CLK100MHZ, Button, output logic UART_RXD_OUT);

logic ButtonNow, ButtonPast, Press;

always_ff @(posedge CLK100MHZ)
begin
    ButtonNow <= Button;
    ButtonPast <= ButtonNow;
end

assign Press = ButtonNow & ~ButtonPast;

uartecho tx_unit(.clk(CLK100MHZ), .Input(10'b1010000010), .Send(Press), .tx(UART_RXD_OUT));

endmodule
