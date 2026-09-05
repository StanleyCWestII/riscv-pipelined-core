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

    pipelined dut(.Clk(clk), .Reset(reset));

    // ---------------------------------------------------------------- clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------------- vcd
    // Waveform dump, off by default. Build with -DVCD to enable:
    //   iverilog -g2012 -DVCD -o sim processor/tb.sv processor/pipelined.sv
    // Then: vvp sim && gtkwave wave.vcd
    `ifdef VCD
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb);
    end
    `endif

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

    // A trap is terminal on this core: Decode holds it and freezes Fetch.
    // Check both the externally visible cause and that Fetch remains parked.
    task automatic check_trap(input logic [1:0] expect_cause);
        logic [31:0] trap_pc;
        if (dut.TrapCause === expect_cause) begin
            pass_test++; pass_total++;
        end
        else begin
            fail_test++; fail_total++;
            $display("  FAIL  %-14s TrapCause  expected %02b  got %02b",
                     current, expect_cause, dut.TrapCause);
        end

        trap_pc = dut.PCF;
        repeat (5) @(posedge clk);
        #1;
        if (dut.PCF === trap_pc) begin
            pass_test++; pass_total++;
        end
        else begin
            fail_test++; fail_total++;
            $display("  FAIL  %-14s PC moved after trap: %08h -> %08h",
                     current, trap_pc, dut.PCF);
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

        // ----------------------------------------- T9: shifts and xor
        run_program("T9 shift/xor", "processor/tests/t9_shift.hex", 400);
        check_reg( 6, 32'h0000_0006);   // xor   12 ^ 10
        check_reg( 7, 32'h0000_0000);   // xor   a ^ a
        check_reg( 8, 32'hFFFF_FFF3);   // xori  NOT 12
        check_reg( 9, 32'h0000_0006);   // xori  12 ^ 10
        check_reg(10, 32'h0000_00C0);   // sll   12 << 4
        check_reg(11, 32'h0000_00C0);   // sll   shift amount 36 masks to 4
        check_reg(12, 32'h0000_00C0);   // slli  12 << 4
        check_reg(21, 32'h0000_000C);   // sll   shift by 0
        check_reg(13, 32'h0FFF_FFFF);   // srl   zero fill
        check_reg(14, 32'h0FFF_FFFF);   // srli  zero fill
        check_reg(19, 32'h0FFF_FFF8);   // srl   0xFFFFFF80 >> 4
        check_reg(15, 32'hFFFF_FFFF);   // sra   sign fill keeps -1
        check_reg(16, 32'hFFFF_FFFF);   // srai  sign fill keeps -1
        check_reg(18, 32'hFFFF_FFF8);   // sra   -128 >> 4 = -8
        check_reg(20, 32'hFFFF_FFF8);   // srai  -128 >> 4 = -8
        report();

        // ------------------------------------ T10: unsigned comparison
        run_program("T10 sltu", "processor/tests/t10_sltu.hex", 400);
        check_reg( 5, 32'h0000_0001);   // slt    -1 < 1          signed
        check_reg( 6, 32'h0000_0000);   // sltu   same bits, unsigned
        check_reg( 7, 32'h0000_0001);   // sltu   1 < 4294967295
        check_reg( 8, 32'h0000_0000);   // sltu   equal
        check_reg( 9, 32'h0000_0001);   // sltu   10 < 12
        check_reg(10, 32'h0000_0000);   // sltu   12 < 10
        check_reg(11, 32'h0000_0001);   // sltiu  1 < 5
        check_reg(12, 32'h0000_0000);   // sltiu  4294967295 < 5
        check_reg(13, 32'h0000_0001);   // slti   signed contrast
        check_reg(14, 32'h0000_0001);   // sltiu  0 < 1
        check_reg(15, 32'h0000_0001);   // sltiu  immediate sign-extends
        report();

        // --------------------------------- T11: all six branch conditions
        // 0 means the branch was taken, 1 means it fell through.
        run_program("T11 branch cond", "processor/tests/t11_branch.hex", 400);
        check_reg(10, 32'h0000_0000);   // beq   5 == 5        taken
        check_reg(11, 32'h0000_0000);   // bne   5 != 3        taken
        check_reg(21, 32'h0000_0001);   // bne   5 != 5        not taken
        check_reg(12, 32'h0000_0000);   // blt   3 <  5        taken
        check_reg(13, 32'h0000_0001);   // blt   5 <  3        not taken
        check_reg(14, 32'h0000_0000);   // bge   5 >= 3        taken
        check_reg(15, 32'h0000_0000);   // bge   5 >= 5        taken on equal
        check_reg(16, 32'h0000_0001);   // bge   3 >= 5        not taken
        check_reg(17, 32'h0000_0000);   // blt   -1 <  1       signed, taken
        check_reg(18, 32'h0000_0001);   // bltu  huge <  1     unsigned, not taken
        check_reg(19, 32'h0000_0001);   // bge   -1 >= 1       signed, not taken
        check_reg(20, 32'h0000_0000);   // bgeu  huge >= 1     unsigned, taken
        report();

        // ------------------------------------------------------- T12: lui
        run_program("T12 lui", "processor/tests/t12_lui.hex", 300);
        check_reg( 5, 32'h1234_5000);   // must ignore the rs1 field (x8 = 0x111)
        check_reg( 1, 32'h0000_1000);   // smallest nonzero
        check_reg( 2, 32'hFFFF_F000);   // all ones, no sign extension
        check_reg( 3, 32'h0000_0000);   // zero
        check_reg( 4, 32'h1234_5678);   // lui + addi builds a 32-bit constant
        check_reg( 6, 32'hABCD_E000);   // lui result
        check_reg( 7, 32'hABCD_E000);   // forwarded out of lui into addi
        check_reg( 8, 32'h0000_0111);   // untouched
        report();

        // ----------------------------------------------------- T13: auipc
        run_program("T13 auipc", "processor/tests/t13_auipc.hex", 300);
        check_reg( 1, 32'h0000_0014);   // PC of the instruction, not PC+4
        check_reg( 2, 32'h0000_1018);   // 0x18 + 0x1000
        check_reg( 3, 32'hFFFF_F01C);   // 0x1c + 0xFFFFF000, wraps cleanly
        check_reg( 5, 32'h1234_5010);   // rs1 field ignored (x8 = 0x111)
        check_reg( 6, 32'h0000_2020);   // 0x20 + 0x2000
        check_reg( 7, 32'h0000_2020);   // forwarded out of auipc into addi
        check_reg( 8, 32'h0000_0111);   // untouched
        report();

        // ------------------------------------------------------ T14: jalr
        run_program("T14 jalr", "processor/tests/t14_jalr.hex", 400);
        check_reg( 1, 32'd8);     // link from first jump
        check_reg( 2, 32'd24);    // AUIPC proves target bit 0 was cleared
        check_reg( 3, 32'd40);    // negative offset, base forwarded from W
        check_reg( 4, 32'd40);    // immediate consumer of link
        check_reg( 6, 32'd60);    // rd == rs1 keeps old base for jump
        check_reg( 7, 32'd60);    // link forwarded at target
        check_reg(10, 32'd96);    // cold load-use dependency
        check_reg(11, 32'd96);
        check_reg(13, 32'd116);   // warm load-use dependency, positive offset
        check_reg(14, 32'd116);
        check_reg(15, 32'd7);     // final target reached; discarded link preserves x0
        check_reg(30, 32'd0);     // wrong-path register writes squashed
        check_mem( 0, 32'd104);   // intended store survives
        check_mem( 1, 32'd0);     // wrong-path stores squashed
        report();

        // -------------------------------------------------------- T15: lb
        run_program("T15 lb", "processor/tests/t15_lb.hex", 400);
        check_reg( 1, 32'h80FF_7F01); // source word built correctly
        check_reg( 2, 32'h0000_0001); // lane 0, positive
        check_reg( 3, 32'h0000_007F); // lane 1, positive
        check_reg( 4, 32'hFFFF_FFFF); // lane 2, negative
        check_reg( 5, 32'hFFFF_FF80); // lane 3, negative
        check_reg(13, 32'h0000_0001); // lbu lane 0
        check_reg(14, 32'h0000_007F); // lbu lane 1
        check_reg(15, 32'h0000_00FF); // lbu lane 2, no sign extension
        check_reg(16, 32'h0000_0080); // lbu lane 3, no sign extension
        check_reg( 7, 32'h0000_0001); // negative offset from nonzero base
        check_reg( 8, 32'hFFFF_FF80); // positive offset from nonzero base
        check_reg(10, 32'h0000_0000); // load-use stall and forwarding
        check_reg(12, 32'h0000_007F); // forwarded base address
        check_mem( 0, 32'h80FF_7F01); // source word reached main memory
        report();

        // -------------------------------------------------------- T16: lh
        run_program("T16 lh/lhu", "processor/tests/t16_lh.hex", 400);
        check_reg( 1, 32'h80FF_7F01); // source word
        check_reg( 2, 32'h0000_7F01); // lh low half, sign bit clear
        check_reg( 3, 32'h0000_7F01); // lhu low half
        check_reg( 4, 32'hFFFF_80FF); // lh high half, sign extension
        check_reg( 5, 32'h0000_80FF); // lhu high half
        check_reg( 7, 32'h0000_7F01); // negative offset from nonzero base
        check_reg( 8, 32'h0000_80FF); // nonzero base, unsigned high half
        check_reg(10, 32'hFFFF_8100); // load-use dependency
        report();

        // ------------------------------------------------------- T17: sb/sh
        run_program("T17 sb/sh", "processor/tests/t17_sb_sh.hex", 400);
        check_reg( 1, 32'hAABB_CCDD); // original word
        check_reg( 6, 32'hAABB_CCDD); // cache-line fill before partial stores
        check_reg( 7, 32'h0000_6655); // halfword source
        check_mem( 0, 32'h6655_5555); // all byte and halfword stores merged
        report();

        // -------------------------------------------------- T18: ecall trap
        run_program("T18 ecall", "processor/tests/t18_ecall.hex", 40);
        check_trap(2'b01);
        check_reg(1, 32'h0000_0007); // older instruction drains and retires
        check_reg(2, 32'h0000_0000); // instruction after ecall never executes
        report();

        // ------------------------------------------------- T19: ebreak trap
        run_program("T19 ebreak", "processor/tests/t19_ebreak.hex", 40);
        check_trap(2'b10);
        check_reg(2, 32'h0000_0000); // instruction after ebreak never executes
        report();

        // -------------------------------------------- T20: fence is a NOP
        run_program("T20 fence", "processor/tests/t20_fence.hex", 100);
        check_reg(1, 32'h0000_0007); // instruction before fence executes
        check_reg(2, 32'h0000_0008); // fence advances; consumer after it executes
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
