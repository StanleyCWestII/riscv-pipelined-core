// Bring-up wrapper: UART echo + VGA through the pipelined core.
// Core clock for this build is 50 MHz (CLK100MHZ divided by 2): the flopped
// DCache build missed 100 MHz timing (WNS -2.35 post-place). One divided
// domain for everything, so no CDC between core and UART. Consequence: the
// UART's hardcoded 868-tick counters now produce 57600 baud, and VGA timings
// run at half speed. Terminal must be set to 57600 for the echo test.
module top(input logic Reset, CLK100MHZ, UART_TXD_IN, output logic UART_RXD_OUT, Hsync, Vsync, output logic [3:0] Red, Green, Blue);

logic clk50 = 1'b0;
always_ff @(posedge CLK100MHZ) clk50 <= ~clk50;

logic Valid, Busy, TxSend;
logic [7:0] Data, TxByte;
logic [11:0] BgColor;

transmitter tx_unit(.clk(clk50), .Input({1'b1, TxByte, 1'b0}), .Send(TxSend), .Busy(Busy), .tx(UART_RXD_OUT));
receiver rx_unit(.Clk(clk50), .Rx(UART_TXD_IN), .Valid(Valid), .Data(Data));
pipelined processor(.Reset(Reset), .Clk(clk50), .TxSend(TxSend), .TxByte(TxByte), .RxData(Data), .RxValid(Valid), .TxBusy(Busy), .VGAReg(BgColor));
vgapatterngenerator generator(.reset(Reset), .clk(clk50), .BgColor(BgColor), .Hsync(Hsync), .Vsync(Vsync), .Red(Red), .Green(Green), .Blue(Blue));

endmodule
