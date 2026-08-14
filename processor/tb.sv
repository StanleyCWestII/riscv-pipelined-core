// =============================================================================
// tb.sv  --  self-checking testbench for the 5-stage pipelined RV32I subset
//
//   iverilog -g2012 -o sim tb.sv pipelined.sv && vvp sim
//
// The DUT has no ports besides clk and reset, so the bench observes it through
// hierarchical references into RegFile and DataMem. Programs are assembled by
// asm.py and loaded into dut.InstrMem while reset is held, which overrides the
// DUT's own $readmemh of memory.hex.
// =============================================================================

`timescale 1ns/1ps

module tb;

    logic clk, reset;

    pipelined dut(.clk(clk), .reset(reset));

    // ---------------------------------------------------------------- clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------ bookkeeping
    int    pass_total, fail_total;
    int    pass_test,  fail_test;
    string current;

    logic [31:0] prog [0:63];

    // ------------------------------------------------- branch predictor stats
    // Pure benchmarking. Nothing here is part of the predictor; it exists so a
    // change to the prediction policy can be compared against a real number.
    //
    // Sampled on the falling edge so BranchE (a register output) and MisPredict
    // (combinational off ALUResultE) have both settled, with no race against
    // the posedge that produced them.
    //
    // A per-cycle count of BranchE would double-count once the cache exists:
    // a memory stall freezes E, so a branch sitting there is re-counted every
    // frozen cycle. Gating on !MemStall counts each branch exactly once, on
    // the cycle it actually advances. (Before the cache, E never stalled and
    // the gate was unnecessary; it is load-bearing now.) Squashed
    // branches never reach E at all, since FlushD and FlushE assert together.
    // Counts are kept per branch PC, indexed PCE[7:2], the same index the 2-bit
    // counter table will use. Every test program parks in a `beq x0,x0,done`
    // spin loop when it finishes, which executes a branch every cycle until the
    // run ends. Lumping that into one total drowns the real branches, so the
    // parking PC is reported on its own line and left out of the totals.
    int branch_test,  mispred_test;
    int branch_total, mispred_total;
    int br_at [0:63];
    int mp_at [0:63];
    logic [5:0] park_idx;           // PCE[7:2] of the spin loop, found per test
    logic       park_found;

    always @(negedge clk)
        if (!reset && dut.BranchE && !dut.MemStall) begin
            br_at[dut.PCE[7:2]]++;
            if (dut.MisPredict) mp_at[dut.PCE[7:2]]++;
        end

    // Cycles from reset release until the parking branch first reaches E, i.e.
    // how long the program's real work actually took. Everything after that is
    // the spin loop and carries no information.
    int   cycles_to_park;
    logic parked;

    always @(negedge clk)
        if (!reset && !parked) begin
            cycles_to_park++;
            if (park_found && dut.PCE[7:2] == park_idx) parked = 1'b1;
        end

    // -------------------------------------------------------------- loading
    // Zero the architectural state the DUT never resets (RegFile and DataMem
    // have no reset in pipelined.sv, so without this they start as X and every
    // "should be untouched" check is meaningless).
    task automatic load_program(input string hexfile);
        for (int i = 0; i < 64; i++) prog[i] = 32'h0000_0000;
        $readmemh(hexfile, prog);
        for (int i = 0; i < 64; i++) dut.InstrMem[i] = prog[i];
        for (int i = 0; i < 64; i++) dut.DataMem[i]  = 32'h0000_0000;
        for (int i = 0; i < 32; i++) dut.RegFile[i]  = 32'h0000_0000;

        // Locate the parking spin loop: a B-type whose branch immediate is 0,
        // i.e. a branch to itself. Every test ends with one.
        //
        // Take the FIRST such word, not the last: asm.py pads all unused
        // instruction memory with this same encoding, so on a short program
        // most of the array matches. The program parks at the first one it
        // reaches and never advances past it, so that is the executed one.
        park_found = 1'b0;
        for (int i = 0; i < 64; i++)
            if (!park_found && prog[i][6:0] == 7'b1100011 &&
                {prog[i][31], prog[i][7], prog[i][30:25], prog[i][11:8], 1'b0} == 13'b0)
            begin
                park_idx   = i[5:0];
                park_found = 1'b1;
            end
    endtask

    task automatic run_program(input string name,
                               input string hexfile,
                               input int    cycles);
        current      = name;
        pass_test    = 0;
        fail_test    = 0;
        branch_test  = 0;
        mispred_test = 0;
        for (int i = 0; i < 64; i++) begin br_at[i] = 0; mp_at[i] = 0; end
        cycles_to_park = 0;
        parked         = 1'b0;

        reset = 1'b0;
        #1 reset = 1'b1;            // rising edge drives the async reset
        @(posedge clk);
        #1 load_program(hexfile);   // safely away from any clock edge
        @(posedge clk);
        #1 reset = 1'b0;

        repeat (cycles) @(posedge clk);
        #1;                         // let the last writeback settle
    endtask

    // --------------------------------------------------------------- checks
    task automatic check_reg(input int unsigned r, input logic [31:0] expect_v);
        if (r == 0) begin           // x0 is never checked directly: the DUT
            $display("  NOTE  %s: skipping direct x0 check", current);
        end
        else if (dut.RegFile[r] === expect_v) begin
            pass_test++; pass_total++;
        end
        else begin
            fail_test++; fail_total++;
            $display("  FAIL  %-14s x%0d  expected %08h  got %08h",
                     current, r, expect_v, dut.RegFile[r]);
        end
    endtask

    task automatic check_mem(input int unsigned word_addr,
                             input logic [31:0] expect_v);
        if (dut.DataMem[word_addr] === expect_v) begin
            pass_test++; pass_total++;
        end
        else begin
            fail_test++; fail_total++;
            $display("  FAIL  %-14s DataMem[%0d] (byte 0x%0h)  expected %08h  got %08h",
                     current, word_addr, word_addr*4,
                     expect_v, dut.DataMem[word_addr]);
        end
    endtask

    task automatic report();
        string verdict;
        verdict = (fail_test == 0) ? "PASS" : "**FAIL**";

        // Totals for this test, parking loop excluded.
        branch_test  = 0;
        mispred_test = 0;
        for (int i = 0; i < 64; i++)
            if (!(park_found && i[5:0] == park_idx)) begin
                branch_test  += br_at[i];
                mispred_test += mp_at[i];
            end
        branch_total  += branch_test;
        mispred_total += mispred_test;

        if (branch_test == 0)
            $display("  %-16s %2d/%2d %s", current, pass_test,
                     pass_test + fail_test, verdict);
        else begin
            $display("  %-16s %2d/%2d %-9s branches %3d   mispredicts %3d   cycles %3d",
                     current, pass_test, pass_test + fail_test, verdict,
                     branch_test, mispred_test, cycles_to_park);
            for (int i = 0; i < 64; i++)
                if (br_at[i] > 0 && !(park_found && i[5:0] == park_idx))
                    $display("                     pc 0x%02h   %3d exec  %3d mispred",
                             i * 4, br_at[i], mp_at[i]);
        end
    endtask

    // ----------------------------------------------------------------- body
    initial begin
        pass_total = 0;
        fail_total = 0;
        $display("");
        $display("=== pipelined RV32I subset: self-checking regression ===");
        $display("");

        // -------------------------------------------------- T1: I-type ALU
        run_program("T1 I-type", "processor/tests/t1_itype.hex", 200);
        check_reg( 1, 32'h0000_0005);
        check_reg( 2, 32'hFFFF_FFFD);   // sign-extended -3
        check_reg( 3, 32'h0000_07FF);   // largest positive immediate
        check_reg( 4, 32'hFFFF_F800);   // most negative immediate
        check_reg( 5, 32'h0000_000D);   // ori   5 | 8
        check_reg( 6, 32'h0000_00F0);   // andi  0x7FF & 0xF0
        check_reg( 7, 32'h0000_0001);   // slti  -3 < 0
        check_reg( 8, 32'h0000_0000);   // slti   5 < 0
        check_reg( 9, 32'h0000_0001);   // slti   5 < 6
        check_reg(10, 32'h0000_0063);
        check_reg(11, 32'h0000_0000);   // x0 still reads zero after being written
        report();

        // -------------------------------------------------- T2: R-type ALU
        run_program("T2 R-type", "processor/tests/t2_rtype.hex", 200);
        check_reg( 3, 32'h0000_0016);   // add  12 + 10
        check_reg( 4, 32'h0000_0002);   // sub  12 - 10
        check_reg( 5, 32'h0000_0008);   // and
        check_reg( 6, 32'h0000_000E);   // or
        check_reg( 7, 32'h0000_0001);   // slt  10 < 12
        check_reg( 8, 32'h0000_0000);   // slt  12 < 10
        check_reg(10, 32'h0000_0001);   // slt  -1 < 0   (signed)
        check_reg(11, 32'h0000_0000);   // slt   0 < -1
        check_reg(12, 32'hFFFF_FFFE);   // sub  10 - 12
        check_reg(13, 32'hFFFF_FFFE);   // add  -1 + -1
        report();

        // ----------------------------------------------- T3: loads / stores
        run_program("T3 load/store", "processor/tests/t3_loadstore.hex", 400);
        check_reg( 3, 32'h0000_002A);   // 42
        check_reg( 4, 32'h0000_0063);   // 99
        check_reg( 6, 32'h0000_0008);
        check_reg( 8, 32'h0000_002A);   // nonzero base + offset
        check_reg( 9, 32'h0000_002A);
        check_mem( 4, 32'h0000_002A);   // sw with forwarded store data
        check_mem( 8, 32'h0000_0063);
        check_mem( 2, 32'h0000_0008);   // sw with forwarded base AND data
        check_mem( 6, 32'h0000_002A);   // sw whose data came from a load
        report();

        // ------------------------------------------------ T4: load-use stall
        run_program("T4 load-use", "processor/tests/t4_loaduse.hex", 300);
        check_reg( 2, 32'h0000_0007);
        check_reg( 3, 32'h0000_000E);   // stall then forward into R-type
        check_reg( 5, 32'h0000_0008);   // stall then forward into I-type
        check_reg( 7, 32'h0000_000E);   // distance 2, no stall required
        check_reg( 8, 32'h0000_0007);
        check_reg(10, 32'h0000_0037);   // branch target reached
        check_reg(30, 32'h0000_0000);   // squashed
        check_reg(31, 32'h0000_0000);   // squashed
        report();

        // --------------------------------------------------- T5: branches
        run_program("T5 branch", "processor/tests/t5_branch.hex", 200);
        check_reg( 4, 32'h0000_0001);
        check_reg( 5, 32'h0000_0002);   // not-taken path must execute
        check_reg( 6, 32'h0000_0003);
        check_reg( 8, 32'h0000_0006);
        check_reg(30, 32'h0000_0000);   // squashed by taken branch
        check_reg(31, 32'h0000_0000);   // squashed
        check_reg(29, 32'h0000_0000);   // squashed
        report();

        // -------------------------------------------------------- T6: jal
        run_program("T6 jal", "processor/tests/t6_jal.hex", 200);
        check_reg( 2, 32'h0000_0008);   // link = address of jal + 4
        check_reg( 3, 32'h0000_0008);   // link used at the target, forwarded
        check_reg( 5, 32'h0000_000C);   // link + 4, still close behind the jal
        check_reg( 4, 32'h0000_0008);
        check_reg(30, 32'h0000_0000);   // squashed
        check_reg(31, 32'h0000_0000);   // squashed
        check_reg(29, 32'h0000_0000);   // squashed
        report();

        // ------------------------------------------- T7: forwarding distance
        run_program("T7 forwarding", "processor/tests/t7_forward.hex", 200);
        check_reg( 2, 32'h0000_0006);   // distance 1, forward from M
        check_reg( 4, 32'h0000_0006);   // distance 2, forward from W
        check_reg( 6, 32'h0000_0006);   // distance 3, negedge regfile write
        check_reg( 8, 32'h0000_0006);   // distance 4, plain read
        check_reg( 9, 32'h0000_0004);   // chained distance-1 dependencies
        check_reg(10, 32'h0000_0007);
        report();

        // ------------------------------- T8: backward loop + SLT overflow
        run_program("T8 loop/overflow", "processor/tests/t8_loop.hex", 2000);
        check_reg( 1, 32'h8000_0000);   // 1 doubled 31 times
        check_reg( 2, 32'h0000_0000);   // loop counter drained
        check_reg( 4, 32'h0000_0001);   // INT_MIN <  1      (subtract overflows)
        check_reg( 5, 32'h0000_0001);   // INT_MIN <  0
        check_reg( 6, 32'h0000_0000);   // 0       < INT_MIN (subtract overflows)
        check_reg( 7, 32'h0000_0001);   // INT_MIN < -1
        check_reg( 9, 32'h0000_0000);   // 1       < INT_MIN (subtract overflows)
        report();

        // ------------------------------------------------------- summary
        $display("");
        $display("=== %0d/%0d checks passed ===",
                 pass_total, pass_total + fail_total);
        if (fail_total == 0) $display("=== ALL TESTS PASSED ===");
        else                 $display("=== %0d FAILURES ===", fail_total);
        $display("");
        $display("=== branch predictor: 2-bit saturating counters, 64 entries ===");
        $display("=== %0d branches, %0d mispredicts, %0d wasted cycles ===",
                 branch_total, mispred_total, 2 * mispred_total);
        $display("=== (parking spin loops excluded from all counts) ===");
        $display("");
        $finish;
    end

    // ------------------------------------------------------------- watchdog
    initial begin
        #100000;
        $display("TIMEOUT: simulation did not finish");
        $finish;
    end

endmodule
