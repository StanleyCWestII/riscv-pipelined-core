`timescale 1ns/1ps

// Runs one riscv-tests rv32ui program on the RTL.
//
//   +hex=<file>       instruction image, objcopy -O verilog, 32-bit words
//   +data=<prefix>    <prefix>0.hex .. <prefix>3.hex, one per DataMem bank
//   +timeout=<n>      cycles before giving up (default 200000)
//
// Completion is ebreak with an empty pipeline (TrapCause == 2'b10). The
// custom riscv_test.h sets a0 = 1 on pass and a0 = 0 on fail, leaving the
// failing case number in gp (x3).
module tb_isa;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [1:0] trap_cause;
    int cycles = 0;
    int timeout = 200000;
    int mispairs = 0;
    logic [31:0] first_mispair_pc = 0;
    string hexfile, dataprefix;

    pipelined dut(
        .Clk(clk),
        .Reset(reset),
        .RxValid(1'b0),
        .TxBusy(1'b0),
        .RxData(8'b0),
        .TrapCause(trap_cause)
    );

    always #5 clk = ~clk;

    initial begin
        if (!$value$plusargs("hex=%s", hexfile))
            $fatal(1, "tb_isa: missing +hex=<file>");
        if (!$value$plusargs("data=%s", dataprefix))
            $fatal(1, "tb_isa: missing +data=<prefix>");
        void'($value$plusargs("timeout=%d", timeout));

        // No architectural reset on these arrays: fill InstrMem with nop so a
        // stray fetch past the end of the program is harmless.
        for (int i = 0; i < 16384; i++) dut.InstrMem[i] = 32'h00000013;
        for (int i = 0; i < 4096; i++) begin
            dut.DataMem0[i] = 32'h00000000;
            dut.DataMem1[i] = 32'h00000000;
            dut.DataMem2[i] = 32'h00000000;
            dut.DataMem3[i] = 32'h00000000;
        end
        for (int i = 0; i < 32; i++) dut.RegFile[i] = 32'h00000000;

        $readmemh(hexfile, dut.InstrMem);
        $readmemh({dataprefix, "0.hex"}, dut.DataMem0);
        $readmemh({dataprefix, "1.hex"}, dut.DataMem1);
        $readmemh({dataprefix, "2.hex"}, dut.DataMem2);
        $readmemh({dataprefix, "3.hex"}, dut.DataMem3);

        repeat (2) @(posedge clk);
        #1 reset = 1'b0;

        while (cycles < timeout) begin
            @(negedge clk);
            cycles++;
            // Integrity check: the word in Decode must be the word instruction
            // memory holds at PCD. A mismatch means Fetch paired an
            // instruction with the wrong PC, which corrupts every PC-relative
            // target downstream even when the test still lands on PASS.
            if (dut.ValidD && !dut.StallD &&
                dut.InstrD !== dut.InstrMem[dut.PCD[15:2]]) begin
                if (mispairs == 0) first_mispair_pc = dut.PCD;
                mispairs++;
            end
            if (trap_cause == 2'b10 && dut.EmptyPipeline) begin
                if (dut.RegFile[10] === 32'd1) begin
                    if (mispairs == 0)
                        $display("ISA PASS cycles=%0d", cycles);
                    else
                        $display("ISA SUSPECT cycles=%0d mispairs=%0d first_pcd=0x%03h",
                                 cycles, mispairs, first_mispair_pc);
                    $finish;
                end
                $display("ISA FAIL testnum=%0d cycles=%0d mispairs=%0d",
                         dut.RegFile[3], cycles, mispairs);
                $finish;
            end
            if (trap_cause == 2'b01 && dut.EmptyPipeline) begin
                $display("ISA FAIL unexpected ecall testnum=%0d cycles=%0d",
                         dut.RegFile[3], cycles);
                $finish;
            end
        end

        $display("ISA TIMEOUT cycles=%0d PCF=0x%08h testnum=%0d",
                 cycles, dut.PCF, dut.RegFile[3]);
        $finish;
    end
endmodule
