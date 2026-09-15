// Execute real loads/stores, then conflict loads to force dirty evictions.
// Checks physical memory independently of the cache-aware core regression.
`timescale 1ns/1ps
module tb_writeback;
    logic clk = 0, reset = 0;
    always #5 clk = ~clk;
    pipelined dut(.Clk(clk), .Reset(reset));
    int pc = 0, passes = 0, failures = 0, evictions = 0;
    int old_tag, old_way, incoming_tag;
    logic [31:0] saved [0:15];
    bit tracking = 0;

    function automatic logic [31:0] memword(input int byte_addr);
        case ((byte_addr >> 2) & 3)
            0: memword = dut.DataMem0[byte_addr >> 4];
            1: memword = dut.DataMem1[byte_addr >> 4];
            2: memword = dut.DataMem2[byte_addr >> 4];
            3: memword = dut.DataMem3[byte_addr >> 4];
        endcase
    endfunction
    task automatic check(input string label, input logic [31:0] got, want);
        if (got === want) passes++;
        else begin
            failures++;
            $display("FAIL %s expected=%h got=%h", label, want, got);
        end
    endtask
    task automatic emit(input logic [31:0] instruction);
        dut.InstrMem[pc] = instruction;
        pc++;
    endtask
    function automatic logic [31:0] addi(input int rd, rs, imm);
        return {12'(imm), 5'(rs), 3'b000, 5'(rd), 7'b0010011};
    endfunction
    function automatic logic [31:0] loadword(input int rd, rs, imm);
        return {12'(imm), 5'(rs), 3'b010, 5'(rd), 7'b0000011};
    endfunction
    function automatic logic [31:0] storeword(input int rs, base, imm);
        return {7'(imm >> 5), 5'(rs), 5'(base), 3'b010, 5'(imm), 7'b0100011};
    endfunction

    always @(posedge clk) begin
        if (!reset && dut.DCacheState == dut.DFetch && dut.DMemReady) begin
            if (dut.Beat == 0) begin
                tracking = dut.DValid[0][dut.Victim] && dut.DDirty[0][dut.Victim];
                if (tracking) begin
                    old_tag = dut.DTag[0][dut.Victim];
                    old_way = dut.Victim;
                    incoming_tag = dut.ALUResultM[15:9];
                    evictions++;
                    for (int w = 0; w < 16; w++) begin
                        saved[w] = dut.DCache[0][old_way][w];
                        check("store updated cached word", saved[w], 100 + old_tag * 16 + w);
                        check("dirty data still deferred before eviction",
                              memword(old_tag * 512 + w * 4),
                              32'h10000000 + old_tag * 128 + w);
                    end
                end
            end
            if (tracking && dut.Beat == 3) begin
                #1;
                for (int w = 0; w < 16; w++) begin
                    check("evicted word reached original DataMem address",
                          memword(old_tag * 512 + w * 4), saved[w]);
                    check("incoming line filled correctly",
                          dut.DCache[0][old_way][w],
                          32'h10000000 + incoming_tag * 128 + w);
                end
                check("replacement line starts clean", dut.DDirty[0][old_way], 0);
                $display("TRACE eviction old_tag=%0d incoming_tag=%0d way=%0d dirty_after=%b",
                         old_tag, incoming_tag, old_way, dut.DDirty[0][old_way]);
                tracking = 0;
            end
        end
    end

    initial begin
        #1 reset = 1;
        #10;
        for (int i = 0; i < 4096; i++) begin
            dut.DataMem0[i] = 32'h10000000 + i * 4;
            dut.DataMem1[i] = 32'h10000001 + i * 4;
            dut.DataMem2[i] = 32'h10000002 + i * 4;
            dut.DataMem3[i] = 32'h10000003 + i * 4;
        end
        for (int i = 0; i < 32; i++) dut.RegFile[i] = 0;
        for (int i = 0; i < 256; i++) dut.InstrMem[i] = 32'h00000063;
        emit(addi(1, 0, 0));
        // Four lines in the same set, all sixteen words changed distinctly.
        for (int line = 0; line < 4; line++) begin
            emit(loadword(3, 1, 0));
            for (int w = 0; w < 16; w++) begin
                emit(addi(2, 0, 100 + line * 16 + w));
                emit(storeword(2, 1, w * 4));
            end
            emit(addi(1, 1, 512));
        end
        emit(loadword(4, 1, 0));
        emit(addi(1, 1, 512));
        emit(loadword(5, 1, 0));
        emit(addi(31, 0, 1));
        emit(32'h00000063);
        @(negedge clk) reset = 0;
        repeat (3000) @(negedge clk);
        check("program completed", dut.RegFile[31], 1);
        check("two dirty evictions exercised", evictions, 2);
        check("first conflict load result", dut.RegFile[4], 32'h10000200);
        check("second conflict load result", dut.RegFile[5], 32'h10000280);
        $display("WRITEBACK: %0d passed, %0d failed", passes, failures);
        if (failures) $fatal(1, "write-back checks failed");
        $finish;
    end
endmodule
