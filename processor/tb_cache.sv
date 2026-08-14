// Cache benchmark harness for the direct-mapped D-cache in pipelined.sv.
//
// Separate from tb.sv on purpose: tb.sv is the 65-check correctness
// regression and its DataMem expectations depend on memory starting zeroed.
// This bench seeds DataMem instead and checks nothing but cache behaviour.
//
// Counting rules, all sampled on the falling edge so the combinational cache
// signals have settled:
//
//   access  MemoryAccess && ~MemStall
//           An access is counted on the cycle it actually completes. A miss
//           holds MemoryAccess high for the whole refill, so counting every
//           cycle would multiply-count it; gating on ~MemStall counts the
//           retry cycle only, exactly once per lw/sw.
//
//   miss    CacheState == Idle && Miss
//           True for exactly one cycle per miss: the cycle the miss is first
//           seen. From the next cycle the FSM is in Fetch.
//
//   stall   MemStall, counted every cycle. This is the real cost paid.
//
// AMAT here is measured, not modelled: (accesses + stall cycles) / accesses.
`timescale 1ns/1ps

module tb_cache;

    logic clk = 0, reset = 1, RxValid = 0, TxBusy = 0;
    logic [7:0] RxData = 0;
    logic TxSend;  logic [7:0] TxByte;  logic [11:0] VGAReg;

    pipelined dut(.clk(clk), .reset(reset), .RxValid(RxValid), .TxBusy(TxBusy),
                  .RxData(RxData), .TxSend(TxSend), .TxByte(TxByte),
                  .VGAReg(VGAReg));

    always #5 clk = ~clk;

    logic [31:0] prog [0:63];
    logic [5:0]  park_idx;
    logic        park_found, parked;
    int          accesses, misses, stalls, cycles;
    string       current;
    int          bi;
    bit          nocache_mode;
    int          base_cy [0:3], cach_cy [0:3];
    real         base_am [0:3], cach_am [0:3];
    string       bn [0:3];
    string       bh [0:3];
    int          bb [0:3];

    // Invalidate one full cycle AFTER an access completes. Clearing during the
    // completing cycle would drop Hit mid-cycle, re-raise Miss and MemStall,
    // and the instruction would never leave M. Clearing during a refill would
    // undo the fill. One cycle late is the only safe window.
    logic acc_done_d;
    always @(posedge clk)
        acc_done_d <= nocache_mode && dut.MemoryAccess && !dut.MemStall;
    always @(negedge clk)
        if (acc_done_d) for (int i = 0; i < 16; i++) dut.Valid[i] = 1'b0;

    always @(negedge clk) if (!reset && !parked) begin
        cycles++;
        if (dut.MemoryAccess && !dut.MemStall)          accesses++;
        if (dut.CacheState == 1'b0 && dut.Miss)         misses++;
        if (dut.MemStall)                               stalls++;
        if (park_found && dut.PCE[7:2] == park_idx)     parked = 1'b1;
    end

    // Baseline: hold every Valid bit low so no lookup can ever hit and every
    // access goes to main memory.
    // That is exactly the machine you would have with 15-cycle memory and no
    // cache at all, measured rather than arithmetic.
    task automatic run_bench(input string name, input string hexfile,
                             input int budget, input bit nocache);
        real hitrate, amat;
        current = name;
        nocache_mode = nocache;
        accesses = 0; misses = 0; stalls = 0; cycles = 0; parked = 0;

        reset = 1'b0;
        #1 reset = 1'b1;
        @(posedge clk);
        #1;
        for (int i = 0; i < 64;  i++) prog[i] = 32'h0;
        $readmemh(hexfile, prog);
        for (int i = 0; i < 64;  i++) dut.InstrMem[i] = prog[i];
        for (int i = 0; i < 32;  i++) dut.RegFile[i]  = 32'h0;
        for (int i = 0; i < 256; i++) dut.DataMem[i]  = i;   // seeded, not zeroed
        for (int i = 0; i < 16;  i++) dut.Valid[i]    = 1'b0;

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
            hitrate = 100.0 * real'(accesses - misses) / real'(accesses);
            amat    = real'(accesses + stalls) / real'(accesses);
            $display("  %-18s %6d %7d %7d %8.1f%% %8d %9.2f %8d",
                     name, accesses, accesses - misses, misses,
                     hitrate, stalls, amat, cycles);
            if (nocache) begin base_cy[bi] = cycles; base_am[bi] = amat; end
            else         begin cach_cy[bi] = cycles; cach_am[bi] = amat; end
        end
    endtask

    initial begin
        $display("");
        $display("=== D-cache: 16 lines x 4 words (64 words), direct-mapped,");
        $display("===          write-through, 15-cycle main memory ===");
        $display("");
        $display("  %-18s %6s %7s %7s %9s %8s %9s %8s",
                 "benchmark", "acc", "hits", "misses", "hit rate",
                 "stall cy", "AMAT", "cycles");
        $display("  %s", {80{"-"}});

        bn[0]="B1 stream";       bh[0]="processor/bench/b1_stream.hex";       bb[0]=3000;
        bn[1]="B2 reuse fits";   bh[1]="processor/bench/b2_reuse_fits.hex";   bb[1]=3000;
        bn[2]="B3 reuse thrash"; bh[2]="processor/bench/b3_reuse_thrash.hex"; bb[2]=12000;
        bn[3]="B4 conflict";     bh[3]="processor/bench/b4_conflict.hex";     bb[3]=3000;

        for (bi = 0; bi < 4; bi++) run_bench(bn[bi], bh[bi], bb[bi], 1'b0);

        $display("");
        $display("=== same programs, 15-cycle memory, NO cache (every access misses) ===");
        $display("");
        $display("  %-18s %6s %7s %7s %9s %8s %9s %8s",
                 "benchmark", "acc", "hits", "misses", "hit rate",
                 "stall cy", "AMAT", "cycles");
        $display("  %s", {80{"-"}});
        for (bi = 0; bi < 4; bi++) run_bench(bn[bi], bh[bi], bb[bi]*6, 1'b1);

        $display("");
        $display("=== what the cache bought ===");
        $display("");
        $display("  %-18s %12s %12s %10s %10s",
                 "benchmark", "cycles w/o", "cycles w/", "speedup", "AMAT");
        $display("  %s", {70{"-"}});
        for (bi = 0; bi < 4; bi++)
            $display("  %-18s %12d %12d %9.2fx  %5.2f -> %.2f",
                     bn[bi], base_cy[bi], cach_cy[bi],
                     real'(base_cy[bi]) / real'(cach_cy[bi]),
                     base_am[bi], cach_am[bi]);
        $display("");
        $finish;
    end

endmodule
