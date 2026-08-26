module transmitter(input logic clk, Send, input logic [9:0] Input, output logic tx, Busy = 0);

logic [3:0] Index = 0;
logic [9:0] Count = 0, InputNext;

// register than freezes Input so it can't be changed mid-cycle
always_ff @(posedge clk)
    if (~Busy && Send) InputNext <= Input;

// register that counts each clk cycle. resets at the 868th cycle
always_ff @(posedge clk)
    begin
        if ((Count == 867) | ~Busy) Count <= 0;
            else if (Busy) Count <= Count + 1;
    end

// mainly Index logic. basically, if Busy, and if Count == 867, Index increments.
// otherwise, if Index == 9 (showing 10 increments across all 10 input bits)
// it ends the cycle and resets Index and Busy back to 0
always_ff @(posedge clk)
    begin
        if (Send && ~Busy) Busy <= 1;
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

// output logic. if ~Busy, holds tx high. if Busy, indexes into InputNext to
// grab the bit
always_comb
    case (Busy)
        1'b0: tx = 1;
        1'b1: tx = InputNext[Index];
    endcase

endmodule
