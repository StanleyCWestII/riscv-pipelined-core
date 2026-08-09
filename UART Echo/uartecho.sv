module uartecho(input logic clk, send, output logic tx);

logic Busy = 0;
logic [3:0] Index = 0;
logic [9:0] Count = 0, Input = 10'b1000000010;

always_ff @(posedge clk)
    begin
        if ((Count == 867) | ~Busy) Count <= 0;
            else if (Busy) Count <= Count + 1;
    end

always_ff @(posedge clk)
    if (send) Busy <= 1;
    else if (~Busy) Index <= 0;
    else if (Count == 867)
    begin
        if (Index == 9)
        begin
            Index <= 0;
            Busy <= 0;
        end
        else if (Busy) Index <= Index + 1;
    end
    else Index <= Index;

always_comb
    case (Busy)
        1'b0: tx = 1;
        1'b1: tx = Input[Index];
    endcase

endmodule
