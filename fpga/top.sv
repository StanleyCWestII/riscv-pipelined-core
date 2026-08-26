module top(input logic Reset, CLK100MHZ, UART_TXD_IN, output logic UART_RXD_OUT, Hsync, Vsync, output logic [3:0] Red, Green, Blue);

logic Valid, Busy, TxSend;
logic [7:0] Data, TxByte;
logic [11:0] BgColor;

transmitter tx_unit(.clk(CLK100MHZ), .Input({1'b1, TxByte, 1'b0}), .Send(TxSend), .Busy(Busy), .tx(UART_RXD_OUT));
receiver rx_unit(.clk(CLK100MHZ), .rx(UART_TXD_IN), .Valid(Valid), .Data(Data));
pipelined processor(.reset(Reset), .clk(CLK100MHZ), .TxSend(TxSend), .TxByte(TxByte), .RxData(Data), .RxValid(Valid), .TxBusy(Busy), .VGAReg(BgColor));
vgapatterngenerator generator(.reset(Reset), .clk(CLK100MHZ), .BgColor(BgColor), .Hsync(Hsync), .Vsync(Vsync), .Red(Red), .Green(Green), .Blue(Blue));

endmodule
