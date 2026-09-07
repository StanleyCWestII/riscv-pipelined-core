// I-cache benchmark harness for the direct-mapped I-cache in pipelined.sv.
//
// Same shape as tb_cache.sv, aimed at fetch instead of loads and stores.
// Runs a few of the regression programs twice: once with the I-cache working,
// once with it defeated, so the "no cache, 15-cycle instruction memory" number
// is measured on the same core rather than estimated.
//
// Counting rules, sampled on the falling edge so combinational signals have
// settled:
//
//   fetch   ~StallF, sampled on the rising edge
//           A fetch is delivered on every edge the fetch stage advances. A
//           miss holds StallF high for the whole refill, so this counts each
//           delivered instruction word exactly once. Wrong-path fetches count
//           too; they are real fetch traffic.
//
//   miss    ICacheState == IIdle && IMiss, sampled on the rising edge
//           One per miss, the edge the FSM leaves Idle.
//
//   stall   IMemStall, every cycle on the falling edge. The cost actually paid.
//
// Defeating the cache: valid bits are cleared one cycle AFTER a fetch is
// delivered, never during. Clearing in the same cycle drops IHit before the
// word is captured and the fetch never completes.
`timescale 1ns/1ps

module tb_icache;

    logic clk = 0, reset = 1, RxValid = 0, TxBusy = 0;
    logic [7:0] RxData = 0;
    logic TxSend;  logic [7:0] TxByte;  logic [11:0] VGAReg;

    pipelined dut(.Clk(clk), .Reset(reset), .RxValid(RxValid), .TxBusy(TxBusy),
                  .RxData(RxData), .TxSend(TxSend), .TxByte(TxByte),
                  .VGAReg(VGAReg));

    always #5 clk = ~clk;

    localparam NB = 4;

    logic [31:0] prog [0:63];
    logic [5:0]  park_idx;
    logic        park_found, parked;
    int          fetches, misses, stalls, cycles;
    bit          nocache_mode;
    int          bi;
    int          base_cy [0:NB-1], cach_cy [0:NB-1];
    real         base_hr [0:NB-1], cach_hr [0:NB-1];
    string       bn [0:NB-1];
    string       bh [0:NB-1];
    int          bb [0:NB-1];

    logic fetched_d;
    always @(posedge clk)
        fetched_d <= nocache_mode && !reset && !dut.StallF;
    always @(negedge clk)
        if (fetched_d)
            for (int i = 0; i < 8; i++) dut.IValid[i] = 1'b0;

    // Fetch and miss are sampled on the rising edge, i.e. the values the
    // pipeline registers are about to act on. Sampling them on the falling
    // edge races the invalidate block above: depending on which block runs
    // first, a fetch that the invalidation is about to cancel gets counted and
    // the miss it creates does not.
    always @(posedge clk) if (!reset && !parked) begin
        if (!dut.StallF)                                  fetches++;
        if (dut.ICacheState == 1'b0 && dut.IMiss)         misses++;
    end

    always @(negedge clk) if (!reset && !parked) begin
        cycles++;
        if (dut.IMemStall)                                stalls++;
        if (park_found && dut.ValidE && dut.PCE[7:2] == park_idx) parked = 1'b1;
    end

    task automatic run_bench(input string name, input string hexfile,
                             input int budget, input bit nocache);
        real hitrate;
        nocache_mode = nocache;
        fetches = 0; misses = 0; stalls = 0; cycles = 0; parked = 0;
        fetched_d = 0;

        reset = 1'b0;
        #1 reset = 1'b1;
        @(posedge clk);
        #1;
        for (int i = 0; i < 64;  i++) prog[i] = 32'h0;
        $readmemh(hexfile, prog);
        for (int i = 0; i < 16384; i++) dut.InstrMem[i] = 32'h0;
        for (int i = 0; i < 64;  i++) dut.InstrMem[i] = prog[i];
        for (int i = 0; i < 32;  i++) dut.RegFile[i]  = 32'h0;
        for (int i = 0; i < 4096; i++) begin
            dut.DataMem0[i] = 32'h0; dut.DataMem1[i] = 32'h0;
            dut.DataMem2[i] = 32'h0; dut.DataMem3[i] = 32'h0;
        end
        for (int i = 0; i < 8; i++) dut.IValid[i] = 1'b0;

        park_found = 1'b0;
        for (int i = 0; i < 64; i++)
            if (!park_found && prog[i][6:0] == 7'b1100011 &&
                {prog[i][31], prog[i][7], prog[i][30:25], prog[i][11:8], 1'b0} == 13'b0)
            begin park_idx = i[5:0]; park_found = 1'b1; end

        @(posedge clk);
        #1 reset = 1'b0;
        repeat (budget) @(posedge clk);
        #1;

        if (!parked)
            $display("  %-18s  DID NOT FINISH in %0d cycles", name, budget);
        else begin
            hitrate = 100.0 * real'(fetches - misses) / real'(fetches);
            $display("  %-18s %7d %7d %7d %8.1f%% %8d %8d",
                     name, fetches, fetches - misses, misses, hitrate, stalls, cycles);
            if (nocache) begin base_cy[bi] = cycles; base_hr[bi] = hitrate; end
            else         begin cach_cy[bi] = cycles; cach_hr[bi] = hitrate; end
        end
    endtask

    initial begin
        $display("");
        $display("=== I-cache: 8 sets x 1 way x 8 words (64 words), direct-mapped,");
        $display("===          15-cycle instruction memory ===");
        $display("");
        $display("  %-18s %7s %7s %7s %9s %8s %8s",
                 "program", "fetch", "hits", "misses", "hit rate", "stall cy", "cycles");
        $display("  %s", {72{"-"}});

        bn[0]="T1 straight-line"; bh[0]="processor/tests/t1_itype.hex";  bb[0]=2000;
        bn[1]="T8 loop";          bh[1]="processor/tests/t8_loop.hex";   bb[1]=6000;
        bn[2]="T14 jalr spread";  bh[2]="processor/tests/t14_jalr.hex";  bb[2]=4000;
        bn[3]="T21 call/ret";     bh[3]="processor/tests/t21_call.hex";  bb[3]=4000;

        for (bi = 0; bi < NB; bi++) run_bench(bn[bi], bh[bi], bb[bi], 1'b0);

        $display("");
        $display("=== same programs, 15-cycle instruction memory, NO cache (every fetch misses) ===");
        $display("");
        $display("  %-18s %7s %7s %7s %9s %8s %8s",
                 "program", "fetch", "hits", "misses", "hit rate", "stall cy", "cycles");
        $display("  %s", {72{"-"}});
        for (bi = 0; bi < NB; bi++) run_bench(bn[bi], bh[bi], bb[bi], 1'b1);

        $display("");
        $display("=== what the I-cache bought ===");
        $display("");
        $display("  %-18s %12s %12s %10s %12s",
                 "program", "cycles w/o", "cycles w/", "speedup", "hit rate");
        $display("  %s", {70{"-"}});
        for (bi = 0; bi < NB; bi++)
            $display("  %-18s %12d %12d %9.2fx  %5.1f%% -> %.1f%%",
                     bn[bi], base_cy[bi], cach_cy[bi],
                     real'(base_cy[bi]) / real'(cach_cy[bi]),
                     base_hr[bi], cach_hr[bi]);
        $display("");
        $finish;
    end

endmodule
