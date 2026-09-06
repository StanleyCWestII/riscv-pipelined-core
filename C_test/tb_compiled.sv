`timescale 1ns/1ps

`ifndef EXPECTED_RETURN
`define EXPECTED_RETURN 10
`endif

// Runs one bare-metal C program on the RTL and checks main's return value.
module tb_compiled;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [1:0] trap_cause;
    int cycles = 0;

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
        // These arrays have no architectural reset, so initialize them before
        // releasing reset. program.hex contains little-endian RV32I words.
        for (int i = 0; i < 16384; i++) dut.InstrMem[i] = 32'h00000013;
        for (int i = 0; i < 4096; i++) begin
            dut.DataMem0[i] = 32'h00000000;
            dut.DataMem1[i] = 32'h00000000;
            dut.DataMem2[i] = 32'h00000000;
            dut.DataMem3[i] = 32'h00000000;
        end
        for (int i = 0; i < 32; i++) dut.RegFile[i] = 32'h00000000;

        $readmemh("C_test/program.hex", dut.InstrMem);
        $readmemh("C_test/data0.hex", dut.DataMem0);
        $readmemh("C_test/data1.hex", dut.DataMem1);
        $readmemh("C_test/data2.hex", dut.DataMem2);
        $readmemh("C_test/data3.hex", dut.DataMem3);

        repeat (2) @(posedge clk);
        #1 reset = 1'b0;

        while (cycles < 500) begin
            @(negedge clk);
            cycles++;
            if (trap_cause == 2'b10 && dut.EmptyPipeline) begin
                if (dut.RegFile[10] === 32'd`EXPECTED_RETURN) begin
                    $display("COMPILED C PASS: main returned %0d in a0 after %0d cycles",
                             dut.RegFile[10], cycles);
                    $finish;
                end
                $fatal(1, "COMPILED C FAIL: expected a0=%0d, got %0d (0x%08h)",
                       `EXPECTED_RETURN, dut.RegFile[10], dut.RegFile[10]);
            end
        end

        $fatal(1, "COMPILED C TIMEOUT after %0d cycles; PCF=0x%08h a0=0x%08h trap=%0d",
               cycles, dut.PCF, dut.RegFile[10], trap_cause);
    end
endmodule
