// tb_top.sv -- integration bench: the pipelined core drives the VGA generator.
//
// This mirrors what top.sv wires together on the board, minus the UART pins.
// It runs vgatest.hex on the real core and checks two separate things:
//
//   Part 1  the colour REGISTER responds to stores at 0x40C and to nothing
//           else. Every change to VGAReg is logged, so a store to the UART
//           at 0x400 or to plain data memory leaking into the VGA register
//           shows up as an extra entry.
//
//   Part 2  the PIXEL OUTPUT actually reflects it. A full 800-tick scanline is
//           swept and every pixel compared against the expected pattern: the
//           seven fixed bars unchanged, the eighth bar carrying the CPU value,
//           and blanking still hard black.
//
// The blanking check is the important one. A monitor needs true black outside
// the visible window or it loses sync, so the programmable colour must appear
// only where VideoOn is high.
//
// PORT CONTRACT -- this bench expects:
//   pipelined            ... output logic [11:0] VGAReg
//   vgapatterngenerator  ... input  logic [11:0] BgColor
// Rename here if you chose different names in the RTL.

`timescale 1ns/1ps

module tb_top;

    logic clk = 0;
    logic reset = 1;

    // core <-> generator
    logic [11:0] VGAReg;

    // UART side, held idle. This bench is not exercising it.
    logic        RxValid = 0;
    logic        TxBusy  = 0;
    logic [7:0]  RxData  = 8'h00;
    logic        TxSend;
    logic [7:0]  TxByte;

    // display side
    logic        Hsync, Vsync;
    logic [3:0]  Red, Green, Blue;

    pipelined core (
        .clk(clk), .reset(reset),
        .RxValid(RxValid), .TxBusy(TxBusy), .RxData(RxData),
        .TxSend(TxSend), .TxByte(TxByte),
        .VGAReg(VGAReg)
    );

    vgapatterngenerator vga (
        .clk(clk), .reset(reset),
        .BgColor(VGAReg),
        .Hsync(Hsync), .Vsync(Vsync),
        .Red(Red), .Green(Green), .Blue(Blue)
    );

    always #5 clk = ~clk;               // 100 MHz

    int passes = 0;
    int fails  = 0;

    task automatic check(input string name, input logic cond);
        if (cond) begin
            passes++;
            $display("  PASS  %s", name);
        end else begin
            fails++;
            $display("  FAIL  %s", name);
        end
    endtask

    // ---------------------------------------------------------------
    // Colour register change log
    // ---------------------------------------------------------------
    logic [11:0] prev_colour;
    int          nchanges = 0;
    logic [11:0] change_log [0:7];

    always @(posedge clk) begin
        if (reset) begin
            prev_colour <= VGAReg;
        end else if (VGAReg !== prev_colour) begin
            if (nchanges < 8) change_log[nchanges] = VGAReg;
            nchanges    = nchanges + 1;
            prev_colour <= VGAReg;
        end
    end

    // ---------------------------------------------------------------
    // Expected pattern. Mirrors vgagenerator.sv, with the last bar
    // replaced by whatever the processor wrote.
    // ---------------------------------------------------------------
    function automatic logic [11:0] expected(input int h, input int v,
                                             input logic [11:0] bg);
        if (h >= 640 || v >= 480) expected = 12'h000;   // blanking, always black
        else if (h <  80) expected = 12'hFFF;
        else if (h < 160) expected = 12'hFF0;
        else if (h < 240) expected = 12'h0FF;
        else if (h < 320) expected = 12'h0F0;
        else if (h < 400) expected = 12'hF0F;
        else if (h < 480) expected = 12'hF00;
        else if (h < 560) expected = 12'h00F;
        else              expected = bg;                // CPU controlled
    endfunction

    logic [31:0] prog [0:63];

    initial begin
        $display("");
        $display("=== core drives VGA: integration ===");
        $display("");

        // Load firmware over the DUT's own $readmemh, same idiom as tb.sv.
        $readmemh("vga/vgatest.hex", prog);
        for (int i = 0; i < 64; i++) core.InstrMem[i] = prog[i];
        for (int i = 0; i < 64; i++) core.DataMem[i]  = 32'h0000_0000;
        for (int i = 0; i < 32; i++) core.RegFile[i]  = 32'h0000_0000;

        repeat (4) @(posedge clk);
        @(negedge clk);
        reset = 0;

        // -----------------------------------------------------------
        // Part 1: the colour register
        // -----------------------------------------------------------
        check("colour register is driven, not X, out of reset", !$isunknown(VGAReg));

        // Give the 10-instruction program room to retire. The stores reach
        // stage M a few cycles behind fetch, so this is generous.
        repeat (200) @(posedge clk);

        check("exactly two writes reached the colour register", nchanges == 2);

        if (nchanges >= 1)
            check("first store put 0x0F0 in the register", change_log[0] === 12'h0F0);
        else
            check("first store put 0x0F0 in the register", 1'b0);

        if (nchanges >= 2)
            check("second store put 0xF00 in the register", change_log[1] === 12'hF00);
        else
            check("second store put 0xF00 in the register", 1'b0);

        check("register settled on 0xF00", VGAReg === 12'hF00);

        if (nchanges > 2) begin
            $display("        %0d changes seen, expected 2. A store to 0x400 or to plain", nchanges);
            $display("        data memory is reaching the VGA register: decode is too loose.");
        end

        // -----------------------------------------------------------
        // Part 2: the pixels
        // -----------------------------------------------------------
        sweep_line(1);      // a visible line
        sweep_line(490);    // a line inside vertical blanking

        $display("");
        if (fails == 0) $display("=== %0d/%0d checks passed ===", passes, passes);
        else            $display("=== %0d/%0d passed, %0d FAILED ===",
                                 passes, passes + fails, fails);
        $display("");
        $finish;
    end

    // Sweep one whole scanline and compare every pixel tick.
    task automatic sweep_line(input int line);
        int    bad;
        int    first_bad_h;
        logic [11:0] got, want;

        bad         = 0;
        first_bad_h = -1;

        // Park at the start of the requested line.
        while (!(vga.Vertical == line && vga.Horizontal == 0)) @(posedge clk);

        for (int h = 0; h < 800; h++) begin
            while (vga.Horizontal != h) @(posedge clk);
            @(negedge clk);                       // sample away from the edge

            got  = {Red, Green, Blue};
            want = expected(h, line, VGAReg);

            if (got !== want) begin
                bad = bad + 1;
                if (first_bad_h < 0) begin
                    first_bad_h = h;
                    $display("        first mismatch on line %0d at h=%0d: got %03h, want %03h",
                             line, h, got, want);
                end
            end

            while (vga.Horizontal == h) @(posedge clk);
        end

        if (line < 480)
            check($sformatf("visible line %0d matches the pattern, last bar = CPU colour", line),
                  bad == 0);
        else
            check($sformatf("blanking line %0d is black across all 800 ticks", line),
                  bad == 0);
    endtask

    // Safety net so a hang does not run forever.
    initial begin
        #50_000_000;
        $display("");
        $display("  TIMEOUT: bench did not finish");
        $finish;
    end

endmodule
