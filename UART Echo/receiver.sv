module receiver(input logic rx, clk, output logic [7:0] Data, output logic Valid);

logic Busy;
logic [3:0] Index = 0;
logic [9:0] Count = 0, InputNext, Storage;

always_ff @(posedge clk)
    if (~Busy && ~rx) InputNext <= Input;

always_ff @(posedge clk)
    begin
        if (Index == 0)
        begin
            if (Count == 1301) Count <= Count + 1;
        end
        else if ((Count == 867) | ~Busy) Count <= 0;
        else if (Busy) Count <= Count + 1;
    end

always_ff @(posedge clk)
    begin
        if (~rx && ~Busy) Busy <= 1;
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
        1'b0: rx = 1;
        1'b1: Storage[Index] = InputNext[Index];
    endcase

always_ff @(posedge clk)
    if (Index == 9) Valid <= 1'b1;
    else Valid <= 1'b0;

assign rx = Storage;

endmodule
