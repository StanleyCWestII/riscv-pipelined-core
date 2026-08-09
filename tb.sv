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
    endtask

    task automatic run_program(input string name,
                               input string hexfile,
                               input int    cycles);
        current    = name;
        pass_test  = 0;
        fail_test  = 0;

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
        $display("  %-16s %2d/%2d %s", current, pass_test,
                 pass_test + fail_test, (fail_test == 0) ? "PASS" : "**FAIL**");
    endtask

    // ----------------------------------------------------------------- body
    initial begin
        pass_total = 0;
        fail_total = 0;
        $display("");
        $display("=== pipelined RV32I subset: self-checking regression ===");
        $display("");

        // -------------------------------------------------- T1: I-type ALU
        run_program("T1 I-type", "tests/t1_itype.hex", 40);
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
        run_program("T2 R-type", "tests/t2_rtype.hex", 40);
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
        run_program("T3 load/store", "tests/t3_loadstore.hex", 40);
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
        run_program("T4 load-use", "tests/t4_loaduse.hex", 50);
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
        run_program("T5 branch", "tests/t5_branch.hex", 50);
        check_reg( 4, 32'h0000_0001);
        check_reg( 5, 32'h0000_0002);   // not-taken path must execute
        check_reg( 6, 32'h0000_0003);
        check_reg( 8, 32'h0000_0006);
        check_reg(30, 32'h0000_0000);   // squashed by taken branch
        check_reg(31, 32'h0000_0000);   // squashed
        check_reg(29, 32'h0000_0000);   // squashed
        report();

        // -------------------------------------------------------- T6: jal
        run_program("T6 jal", "tests/t6_jal.hex", 40);
        check_reg( 2, 32'h0000_0008);   // link = address of jal + 4
        check_reg( 3, 32'h0000_0008);   // link used at the target, forwarded
        check_reg( 5, 32'h0000_000C);   // link + 4, still close behind the jal
        check_reg( 4, 32'h0000_0008);
        check_reg(30, 32'h0000_0000);   // squashed
        check_reg(31, 32'h0000_0000);   // squashed
        check_reg(29, 32'h0000_0000);   // squashed
        report();

        // ------------------------------------------- T7: forwarding distance
        run_program("T7 forwarding", "tests/t7_forward.hex", 50);
        check_reg( 2, 32'h0000_0006);   // distance 1, forward from M
        check_reg( 4, 32'h0000_0006);   // distance 2, forward from W
        check_reg( 6, 32'h0000_0006);   // distance 3, negedge regfile write
        check_reg( 8, 32'h0000_0006);   // distance 4, plain read
        check_reg( 9, 32'h0000_0004);   // chained distance-1 dependencies
        check_reg(10, 32'h0000_0007);
        report();

        // ------------------------------- T8: backward loop + SLT overflow
        run_program("T8 loop/overflow", "tests/t8_loop.hex", 400);
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
        $finish;
    end

    // ------------------------------------------------------------- watchdog
    initial begin
        #100000;
        $display("TIMEOUT: simulation did not finish");
        $finish;
    end

endmodule
