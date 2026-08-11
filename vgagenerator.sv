module vgapatterngenerator(input logic clk, reset, output logic Hsync, Vsync, output logic [3:0] Red, Green, Blue);

logic [9:0] Horizontal, Vertical;
logic [1:0] clkEnable;
logic Ready, VideoOn;

// all from VESA standard for 640x480 at 60hz
parameter int H_VISIBLE = 640;
parameter int H_FRONT = 16;
parameter int H_SYNC = 96;
parameter int H_BACK = 48;
parameter int H_TOTAL = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;

parameter int V_VISIBLE = 480;
parameter int V_FRONT = 10;
parameter int V_SYNC = 2;
parameter int V_BACK = 33;
parameter int V_TOTAL = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;

// Ready signal = 1 on the fourth clock cycle, making it operate on 25MHz
assign Ready = (clkEnable == 3);

// adds 1 to clkEnable every clk cycle, resets on 4th
always_ff @(posedge clk, posedge reset)
    if (reset) clkEnable <= 0;
    else clkEnable <= clkEnable + 1;

// walks the screen in the horizontal and vertical directions
always_ff @(posedge clk)
    begin
        if (reset)
        begin
            Horizontal <= 0;
            Vertical <= 0;
        end
        else if (Ready)
        begin
            Horizontal <= Horizontal + 1;
            if (Horizontal == H_TOTAL - 1)
            begin
                Horizontal <= 0;
                if (Vertical == V_TOTAL - 1)
                begin
                    Vertical <= 0;
                end
                else Vertical <= Vertical + 1;
            end
        end
    end

// Hsync
assign Hsync = ~((Horizontal >= H_VISIBLE + H_FRONT) && (Horizontal < H_VISIBLE + H_FRONT + H_SYNC));
assign Vsync = ~((Vertical >= V_VISIBLE + V_FRONT) && (Vertical < V_VISIBLE + V_FRONT + V_SYNC));
assign VideoOn = ((Horizontal < H_VISIBLE) && (Vertical < V_VISIBLE));

always_comb
    begin
        if (!VideoOn) {Red, Green, Blue} = 12'h000;
        else if (Horizontal < 80) {Red, Green, Blue} = 12'hFFF;
        else if (Horizontal < 160) {Red, Green, Blue} = 12'hFF0;
        else if (Horizontal < 240) {Red, Green, Blue} = 12'h0FF;
        else if (Horizontal < 320) {Red, Green, Blue} = 12'h0F0;
        else if (Horizontal < 400) {Red, Green, Blue} = 12'hF0F;
        else if (Horizontal < 480) {Red, Green, Blue} = 12'hF00;
        else if (Horizontal < 560) {Red, Green, Blue} = 12'h00F;
        else {Red, Green, Blue} = 12'h000;
    end

endmodule
