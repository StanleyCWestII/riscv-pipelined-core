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
    begin
        if (send) Busy <= 1;
        if (Busy)
        begin
            if (Count == 867)
            begin
                if (Index == 9)
                begin
                    Busy <= 0;
                    Index <= 0;
                end
                else Index <= Index + 1;
            end
        end
        else if (~Busy) Index <= 0;
        else Index <= Index;
    end

always_comb
    case (Busy)
        1'b0: tx = 1;
        1'b1: tx = Input[Index];
    endcase

endmodule
