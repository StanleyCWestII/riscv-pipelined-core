// What a UART Echo is:
// You input a character in a terminal, and it "echoes" it back.

// From start to finish,
// Terminal --> USB Cable --> FT2232H Channel B --> FPGA pin C4
// --> receiver.sv --> processor --> transmitter.sv -->
// FT2232H pin D4 --> USB Cable --> Terminal

// Rx is the wire coming in from the FT2232H on pin C4. it idles high,
// then the low start bit, 8 data bits LSB first, and the high stop bit.

// Clk is the 100MHz board clock. The terminal is set at 115200 baud
// (where baud is bits per second), so the receiver must also operate
// at 115200 baud. To do this, 100MHz / 115200 baud = 868 ticks per second.
// However, the first sample must not be on the clock edge, or a forbidden
// value is taken. So we sample in the middle: 868 * 1.5 = 1302.

// Data is purely the assembled byte. It consists of all 8 bits from rx.

// Valid determines when to sample from Data. Data may contain garbage.

module receiver(input logic Rx, Clk, output logic [7:0] Data, output logic Valid);

// Sync1 and Sync2 prevent metastability in the design. Rx comes from
// FT2232H, which is not in sync with the board's clock. They're initialized
// to 1 because the start bit is 0.

// Busy answers whether the design is receiving any bits.
logic Busy = 0, Sync1 = 1, Sync2 = 1;

// Index tells which bit of the full byte we are on.
logic [3:0] Index = 0;

// Count is used for the tick to 1301 and 868.
logic [10:0] Count = 0;

// Storage is used to accumulate the full byte before it is sent out.
logic [7:0] Storage;

// Used as a safeguard for Rx. Sync1 samples directly from Rx and is
// given a clock cycle to stabilize. Then Sync2 samples from Sync1, two
// cycles later.
always_ff @(posedge Clk)
    begin
        Sync1 <= Rx;
        Sync2 <= Sync1;
    end

always_ff @(posedge Clk)
    begin
        if (Index == 0)
        begin
            if (Count == 1301 | ~Busy) Count <= 1'b0;
            else Count <= Count + 1;
        end
        else if ((Count == 867) | ~Busy) Count <= 0;
        else if (Busy) Count <= Count + 1;
    end

always_ff @(posedge Clk)
    begin
        if (~Sync2 && ~Busy) Busy <= 1;
        if (Busy)
        begin
            if (Index == 0)
            begin
                if (Count == 1301) Index <= Index + 1;
            end
            else if (Count == 867)
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

always_ff @(posedge Clk)
    if (Busy && Count == 867 && Index == 7) Valid <= 1'b1;
    else Valid <= 1'b0;

always_ff @(posedge Clk)
    if (Busy && Count == 1301 && Index < 8) Storage[Index] <= Sync2;
    else if (Busy && Count == 867 && Index < 8) Storage[Index] <= Sync2;

assign Data = Storage[7:0];

endmodule
