module receiver(input logic rx, clk, output logic [7:0] Data, output logic Valid);

logic Busy = 0, Sync1 = 1, Sync2 = 1;
logic [3:0] Index = 0;
logic [9:0] Count = 0, Storage;

always_ff @(posedge clk)
    begin
        Sync1 <= rx;
        Sync2 <= Sync1;
    end

always_ff @(posedge clk)
    begin
        if (Index == 0)
        begin
            if (Count == 1301 | ~Busy) Count <= 1'b0;
            else Count <= Count + 1;
        end
        else if ((Count == 867) | ~Busy) Count <= 0;
        else if (Busy) Count <= Count + 1;
    end

always_ff @(posedge clk)
    begin
        if (~Sync2 && ~Busy) Busy <= 1;
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

always_ff @(posedge clk)
    if (Busy && Count == 867 && Index == 7) Valid <= 1'b1;
    else Valid <= 1'b0;

always_ff @(posedge clk)
    if (Busy && Count == 1301) Storage[Index] <= Sync2;
    else if (Busy && Count == 867) Storage[Index] <= Sync2;

assign Data = Storage[7:0];

endmodule
