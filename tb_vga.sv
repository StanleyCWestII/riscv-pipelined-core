// Self-checking testbench for vgapatterngenerator.
//
// The design stays yours. This just watches it run and grades the timing.
//
//   iverilog -g2012 -o vgasim tb_vga.sv vgagenerator.sv && ./vgasim
//
// Checks, in order:
//   1. reset actually clears the counters
//   2. Ready pulses exactly one clock in four   (100 MHz -> 25 MHz)
//   3. Horizontal advances once per Ready, never exceeds H_TOTAL-1
//   4. Vertical advances exactly once per Horizontal wrap
//   5. Vertical never exceeds V_TOTAL-1
//   6. one full frame is exactly H_TOTAL * V_TOTAL pixel ticks
//   7. the resulting refresh rate is ~60 Hz

`timescale 1ns/1ps

module tb_vga;

    localparam int H_VISIBLE = 640;
    localparam int V_VISIBLE = 480;
    localparam int H_TOTAL   = 800;
    localparam int V_TOTAL   = 525;

    // sync phase boundaries, [lo, hi)
    localparam int H_SYNC_LO = 656, H_SYNC_HI = 752;
    localparam int V_SYNC_LO = 490, V_SYNC_HI = 492;

    // one bit per possible 12-bit color, set when seen on a visible line
    logic [4095:0] barSeen = '0;

    logic clk = 0;
    logic reset;

    logic       Hsync, Vsync;
    logic [3:0] Red, Green, Blue;

    // BgColor is tied to black here on purpose. This bench verifies VESA
    // timing, sync polarity, and blanking with the generator standalone, so
    // bar 8 is held at the constant it had before it became programmable and
    // all nine original checks keep their original meaning. The CPU-driven
    // path is covered separately by tb_top.sv.
    vgapatterngenerator dut (
        .clk(clk), .reset(reset),
        .BgColor(12'h000),
        .Hsync(Hsync), .Vsync(Vsync),
        .Red(Red), .Green(Green), .Blue(Blue)
    );

    // 100 MHz board clock
    always #5 clk = ~clk;

    int errors = 0;

    task check(input bit ok, input string what);
        if (!ok) begin
            errors++;
            if (errors <= 10) $display("  FAIL  %s", what);
        end
    endtask

    // ---------------------------------------------------------------
    // observers
    // ---------------------------------------------------------------
    int  readyCount   = 0;   // Ready pulses seen
    int  clkCount     = 0;   // clocks seen since reset released
    int  hWraps       = 0;   // Horizontal 799 -> 0 transitions
    int  vAdvances    = 0;   // Vertical changes
    int  pixelTicks   = 0;   // Ready pulses in the frame under test
    bit  watching     = 0;

    logic [9:0] prevH, prevV;

    always @(posedge clk) begin
        if (watching) begin
            clkCount++;
            if (dut.Ready) readyCount++;

            // range checks, every clock
            check(dut.Horizontal <= H_TOTAL-1, $sformatf(
                  "Horizontal reached %0d, max legal is %0d",
                  dut.Horizontal, H_TOTAL-1));
            check(dut.Vertical <= V_TOTAL-1, $sformatf(
                  "Vertical reached %0d, max legal is %0d",
                  dut.Vertical, V_TOTAL-1));

            // Vertical may only change on a Horizontal wrap
            if (dut.Vertical !== prevV) begin
                vAdvances++;
                check(prevH == H_TOTAL-1, $sformatf(
                      "Vertical changed %0d->%0d mid-line, Horizontal was %0d",
                      prevV, dut.Vertical, prevH));
            end

            if (prevH == H_TOTAL-1 && dut.Horizontal == 0) hWraps++;

            // --- sync polarity: low only inside the sync phase ---
            if (dut.Horizontal >= H_SYNC_LO && dut.Horizontal < H_SYNC_HI)
                check(Hsync === 1'b0, $sformatf(
                      "Hsync is %b at Horizontal=%0d, should be LOW in sync",
                      Hsync, dut.Horizontal));
            else
                check(Hsync === 1'b1, $sformatf(
                      "Hsync is %b at Horizontal=%0d, should be HIGH outside sync",
                      Hsync, dut.Horizontal));

            if (dut.Vertical >= V_SYNC_LO && dut.Vertical < V_SYNC_HI)
                check(Vsync === 1'b0, $sformatf(
                      "Vsync is %b at Vertical=%0d, should be LOW in sync",
                      Vsync, dut.Vertical));
            else
                check(Vsync === 1'b1, $sformatf(
                      "Vsync is %b at Vertical=%0d, should be HIGH outside sync",
                      Vsync, dut.Vertical));

            // --- blanking: RGB must be exactly 0 outside the visible box ---
            if (dut.Horizontal >= H_VISIBLE || dut.Vertical >= V_VISIBLE)
                check({Red,Green,Blue} === 12'h000, $sformatf(
                      "RGB is %03h at (%0d,%0d), must be 000 during blanking",
                      {Red,Green,Blue}, dut.Horizontal, dut.Vertical));
            else begin
                // visible: must be a real value, never x (catches inferred latches)
                check(^{Red,Green,Blue} !== 1'bx, $sformatf(
                      "RGB is %03h at (%0d,%0d), unknown bits in the visible area",
                      {Red,Green,Blue}, dut.Horizontal, dut.Vertical));
                if (dut.Vertical == 0) barSeen[{Red,Green,Blue}] <= 1'b1;
            end
        end
        prevH <= dut.Horizontal;
        prevV <= dut.Vertical;
    end

    // ---------------------------------------------------------------
    initial begin
        $display("\n=== vga timing ===\n");

        reset = 1;
        repeat (5) @(posedge clk);
        @(negedge clk);

        // 1. reset clears the counters
        check(dut.Horizontal === 10'd0, $sformatf(
              "after reset Horizontal is %0d, want 0", dut.Horizontal));
        check(dut.Vertical === 10'd0, $sformatf(
              "after reset Vertical is %0d, want 0", dut.Vertical));
        if (errors == 0) $display("  PASS  reset clears both counters");

        reset   = 0;
        prevH   = 0;
        prevV   = 0;
        watching = 1;

        // 2. Ready duty cycle, measured over 4000 clocks
        repeat (4000) @(posedge clk);
        begin
            int want;
            want = 4000 / 4;
            check(readyCount == want, $sformatf(
                  "Ready pulsed %0d in 4000 clocks (want %0d), pixel clock %0.2f MHz",
                  readyCount, want, 100.0 * readyCount / 4000.0));
            if (readyCount == want)
                $display("  PASS  Ready is 1-in-4, pixel clock 25.00 MHz");
        end

        // If the pixel enable never fires, everything downstream is noise.
        // Say why, once, and stop.
        if (readyCount == 0) begin
            $display("");
            if (dut.Ready === 1'bx || dut.clkEnable === 2'bxx)
                $display("  Ready is x, because clkEnable is x. clkEnable has no");
            else
                $display("  Ready never pulsed. clkEnable is stuck at %0d.", dut.clkEnable);
            $display("  reset and no initial value, so it starts unknown and x+1 is x.");
            $display("  (Real hardware is fine: the bitstream inits registers to 0.)");
            $display("");
            $display("%0d check(s) failed", errors);
            $display("");
            $finish;
        end

        // 3/4/5 run continuously in the observer above.
        // 6. time one whole frame, wrap to wrap.
        @(posedge clk);
        while (!(dut.Ready && dut.Horizontal == H_TOTAL-1
                           && dut.Vertical  == V_TOTAL-1)) @(posedge clk);
        @(posedge clk);

        begin
            int startClk, startH, startV;
            startClk = clkCount;
            startH   = hWraps;
            startV   = vAdvances;

            while (!(dut.Ready && dut.Horizontal == H_TOTAL-1
                               && dut.Vertical  == V_TOTAL-1)) @(posedge clk);
            @(posedge clk);

            pixelTicks = (clkCount - startClk) / 4;

            check(pixelTicks == H_TOTAL * V_TOTAL, $sformatf(
                  "frame took %0d pixel ticks, want %0d",
                  pixelTicks, H_TOTAL * V_TOTAL));
            if (pixelTicks == H_TOTAL * V_TOTAL)
                $display("  PASS  frame is %0d x %0d = %0d pixel ticks",
                         H_TOTAL, V_TOTAL, H_TOTAL * V_TOTAL);

            check((hWraps - startH) == V_TOTAL, $sformatf(
                  "%0d line wraps per frame, want %0d",
                  hWraps - startH, V_TOTAL));
            if ((hWraps - startH) == V_TOTAL)
                $display("  PASS  %0d line wraps per frame", V_TOTAL);

            check((vAdvances - startV) == V_TOTAL, $sformatf(
                  "Vertical advanced %0d times per frame, want %0d",
                  vAdvances - startV, V_TOTAL));
            if ((vAdvances - startV) == V_TOTAL)
                $display("  PASS  Vertical advances exactly once per line");

            // 7. refresh rate
            begin
                real hz;
                hz = 25.0e6 / (H_TOTAL * V_TOTAL);
                if (pixelTicks == H_TOTAL * V_TOTAL)
                    $display("  PASS  refresh rate %0.2f Hz", hz);
            end

            // 8. sync polarity and blanking ran continuously above
            if (errors == 0) begin
                $display("  PASS  Hsync/Vsync low only inside their sync phase");
                $display("  PASS  RGB is 000 throughout every blanking interval");
                $display("  PASS  %0d distinct colors across the visible line",
                         $countones(barSeen));
            end
        end

        $display("");
        if (errors == 0) $display("all checks passed\n");
        else             $display("%0d check(s) failed\n", errors);
        $finish;
    end

    // watchdog, in case the counters never move
    initial begin
        #40_000_000;
        $display("\n  TIMEOUT  counters never completed a frame.");
        $display("           Horizontal=%0d Vertical=%0d clkEnable=%0d Ready=%b\n",
                 dut.Horizontal, dut.Vertical, dut.clkEnable, dut.Ready);
        $finish;
    end

endmodule
