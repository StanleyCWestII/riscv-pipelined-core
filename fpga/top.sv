module top(input logic Reset, CLK100MHZ, UART_TXD_IN, output logic UART_RXD_OUT, Hsync, Vsync, output logic [3:0] Red, Green, Blue);

logic Valid, Busy, TxSend;
logic [7:0] Data, TxByte;
logic [11:0] BgColor;

transmitter tx_unit(.Clk(CLK100MHZ), .Input({1'b1, TxByte, 1'b0}), .Send(TxSend), .Busy(Busy), .Tx(UART_RXD_OUT));
receiver rx_unit(.Clk(CLK100MHZ), .Rx(UART_TXD_IN), .Valid(Valid), .Data(Data));
pipelined processor(.Reset(Reset), .Clk(CLK100MHZ), .TxSend(TxSend), .TxByte(TxByte), .RxData(Data), .RxValid(Valid), .TxBusy(Busy), .VGAReg(BgColor));
vgapatterngenerator generator(.Reset(Reset), .Clk(CLK100MHZ), .BgColor(BgColor), .Hsync(Hsync), .Vsync(Vsync), .Red(Red), .Green(Green), .Blue(Blue));

endmodule
