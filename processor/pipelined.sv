module pipelined(input logic clk, reset, RxValid, TxBusy, input logic [7:0] RxData, output logic TxSend, output logic [7:0] TxByte, output logic [11:0] VGAReg);

// Control Unit declarations
logic [6:0] Op;
logic [2:0] Funct3;
logic [1:0] ALUOp;
logic Funct7;

// Decode Control
logic [2:0] ALUControlD;
logic [1:0] ImmSrcD, ResultSrcD;
logic MemWriteD, ALUSrcD, RegWriteD, BranchD, JumpD;
// Execute Control
logic [2:0] ALUControlE;
logic [1:0] ResultSrcE, PCSrcE;
logic MemWriteE, ALUSrcE, RegWriteE, BranchE, JumpE, ZeroE;
// Memory Control
logic [1:0] ResultSrcM;
logic MemWriteM, RegWriteM;
// Writeback Control
logic [1:0] ResultSrcW;
logic RegWriteW;

// Instruction Memory declarations
logic [31:0] InstrMem [0:63];

// Register Memory declarations
logic [31:0] RegFile [31:0];

// Data Memory declarations
logic [31:0] DataMem [0:255];

// Pipelined Register declarations
// Fetch
logic [31:0] PCFNext, PCF, PCPlus4F, InstrF;
// Decode
logic [31:0] InstrD, PCD, PCPlus4D, ImmExtD, RD1D, RD2D;
logic [4:0] A1D, A2D, A3D;
// Execute
logic [31:0] RD1E, RD2E, PCE, ImmExtE, PCPlus4E, PCTargetE, ALUResultE, SrcAE, SrcBE, ALUSumE, ALUSrcBE, ZeroExtE;
logic [4:0] A3E;
logic SubtractE, N1E, N2E, oVerflowE, SltResultE;
// Memory
logic[31:0] WDM, RDM, PCPlus4M, ALUResultM;
logic [4:0] A3M;
// Writeback
logic [31:0] ALUResultW, PCPlus4W, RDW, WD3W;
logic [4:0] A3W;

// HAZARD Unit declarations
logic [31:0] RD2EI;
logic [4:0] A1E, A2E;
logic [1:0] ForwardAE, ForwardBE;
logic StallF, StallD, FlushE, FlushD, lwStall, ReadsRS1, ReadsRS2,
StallE, StallM, StallW;

// UART Echo declarations
logic RxReady;

// Branch Prediction declarations
logic isBranchF, isBranchD, isBranchE, MisPredict, PredictedF, PredictedD, PredictedE;
logic [31:0] PCTargetF;
logic [1:0] BranchState [0:63];
logic [1:0] BranchNextState;

// Memory Hierarchy declarations
logic Valid [0:15]; // 16 registers each holding a bit
logic [1:0] Tag [0:15]; // 16 registers each holding 2 bits
logic [31:0] DCache [0:15][0:3]; // 16 blocks, 4 words
logic CacheState, CacheNextState, Hit, Miss, MemoryAccess,
MemReady = 1'b1, MemStall;

// Control Unit logic
assign Op = InstrD[6:0];
assign Funct3 = InstrD[14:12];
assign Funct7 = InstrD[30];

// Main Decoder
always_comb
    case (Op)
    // lw
    7'b0000011: {RegWriteD, ImmSrcD, ALUSrcD, MemWriteD, ResultSrcD, BranchD, ALUOp, JumpD, ReadsRS1, ReadsRS2} = 13'b1_00_1_0_01_0_00_0_1_0;
    // sw
    7'b0100011: {RegWriteD, ImmSrcD, ALUSrcD, MemWriteD, ResultSrcD, BranchD, ALUOp, JumpD, ReadsRS1, ReadsRS2} = 13'b0_01_1_1_00_0_00_0_1_1;
    // R-type
    7'b0110011: {RegWriteD, ImmSrcD, ALUSrcD, MemWriteD, ResultSrcD, BranchD, ALUOp, JumpD, ReadsRS1, ReadsRS2} = 13'b1_xx_0_0_00_0_10_0_1_1;
    // beq
    7'b1100011: {RegWriteD, ImmSrcD, ALUSrcD, MemWriteD, ResultSrcD, BranchD, ALUOp, JumpD, ReadsRS1, ReadsRS2} = 13'b0_10_0_0_00_1_01_0_1_1;
    // I-type ALU
    7'b0010011: {RegWriteD, ImmSrcD, ALUSrcD, MemWriteD, ResultSrcD, BranchD, ALUOp, JumpD, ReadsRS1, ReadsRS2} = 13'b1_00_1_0_00_0_10_0_1_0;
    // jal
    7'b1101111: {RegWriteD, ImmSrcD, ALUSrcD, MemWriteD, ResultSrcD, BranchD, ALUOp, JumpD, ReadsRS1, ReadsRS2} = 13'b1_11_1_0_10_0_00_1_0_0;
    default: {RegWriteD, ImmSrcD, ALUSrcD, MemWriteD, ResultSrcD, BranchD, ALUOp, JumpD, ReadsRS1, ReadsRS2} = 13'b0_00_0_0_00_0_00_0_1_0;
endcase

// ALU Decoder
always_comb
    case (ALUOp)
        2'b00: ALUControlD = 3'b000;
        2'b01: ALUControlD = 3'b001;
        2'b10:
        begin
        case (Funct3)
            3'b000:
            begin
                case ({Op[5], Funct7})
                    2'b11: ALUControlD = 3'b001;
                    default: ALUControlD = 3'b000;
                endcase
            end
            3'b010: ALUControlD = 3'b101;
            3'b110: ALUControlD = 3'b011;
            3'b111: ALUControlD = 3'b010;
            default: ALUControlD = 3'b000;
        endcase
        end
        default: ALUControlD = 3'b000;
    endcase

// Zero and PCSrc Logic
always_comb
    case (ALUResultE)
        32'b0: ZeroE = 1'b1;
        default: ZeroE = 1'b0;
    endcase

assign MisPredict = ZeroE ^ PredictedE;

always_comb
begin
	if ((BranchE && MisPredict) | JumpE) PCSrcE = 2'b01;
	else if (isBranchF && PredictedF) PCSrcE = 2'b10;
	else PCSrcE = 2'b00;
end

// Branch Prediction FSM
localparam StronglyTaken = 2'b00;
localparam WeaklyTaken = 2'b01;
localparam WeaklyNotTaken = 2'b10;
localparam StronglyNotTaken = 2'b11;

always_ff @(posedge clk, posedge reset)
    if (reset)
        begin
            for (int i = 0; i < 64; ++i)
            begin
                BranchState[i] <= WeaklyTaken;
            end
        end
    else if (BranchE) BranchState[PCE[7:2]] <= BranchNextState;

always_comb
    begin
        case (BranchState[PCE[7:2]])
            StronglyTaken: BranchNextState = ZeroE ? StronglyTaken : WeaklyTaken;
            WeaklyTaken: BranchNextState = ZeroE ? StronglyTaken : WeaklyNotTaken;
            WeaklyNotTaken: BranchNextState = ZeroE ? WeaklyTaken : StronglyNotTaken;
            StronglyNotTaken: BranchNextState = ZeroE ? WeaklyNotTaken : StronglyNotTaken;
        endcase
    end


// Memory Hierarchy FSM
localparam Idle = 1'b0;
localparam Fetch = 1'b1;

always_ff @(posedge clk, posedge reset)
    if (reset)
        begin
            CacheState <= Idle;
            for (int i = 0; i < 16; ++i)
            begin
                Valid[i] <= 0;
            end
        end
    else
    begin
        CacheState <= CacheNextState;

        if (CacheState == Fetch && MemReady)
        begin
            Valid[ALUResultM[7:4]] <= 1'b1;
            Tag[ALUResultM[7:4]] <= ALUResultM[9:8];
            DCache[ALUResultM[7:4]][0] <= DataMem[{ALUResultM[9:4], 2'b00}];
            DCache[ALUResultM[7:4]][1] <= DataMem[{ALUResultM[9:4], 2'b01}];
            DCache[ALUResultM[7:4]][2] <= DataMem[{ALUResultM[9:4], 2'b10}];
            DCache[ALUResultM[7:4]][3] <= DataMem[{ALUResultM[9:4], 2'b11}];
        end
    end

always_comb
    case (CacheState)
        Idle:
        begin
            MemStall = Miss;
            CacheNextState = Miss ? Fetch : Idle;
        end
        Fetch:
        begin
            MemStall = 1;
            if (MemReady) CacheNextState = Idle;
            else CacheNextState = Fetch;
        end
    endcase

// Program Counter logic
always_ff @(posedge clk, posedge reset)
    if (reset) PCF <= 0;
    else if (~StallF) PCF <= PCFNext;

assign PCPlus4F = PCF + 4;
assign PCTargetF = PCF + {{20{InstrF[31]}}, InstrF[7], InstrF[30:25], InstrF[11:8], 1'b0};

always_comb
    case (PCSrcE)
        2'b00: PCFNext = PCPlus4F;
        2'b01:
        begin
            if (isBranchE == 1'b1 && ZeroE == 1'b0) PCFNext = PCPlus4E;
            else PCFNext = PCTargetE;
        end
        2'b10: PCFNext = PCTargetF;
        default: PCFNext = PCPlus4F;
    endcase

// Instruction Memory logic
initial $readmemh("memory.hex", InstrMem);
assign InstrF = InstrMem[PCF[7:2]];

// Branch Prediction logic
always_comb
begin
	if (InstrF[6:0] == 7'b1100011) isBranchF = 1;
	else isBranchF = 0;
end

assign PredictedF = ~BranchState[PCF[7:2]][1];

// Fetch --> Decode Register
always_ff @(posedge clk, posedge reset)
    if (reset | FlushD)
    begin
        InstrD <= 0;
        PCD <= 0;
        PCPlus4D <= 0;
        isBranchD <= 0;
        PredictedD <= 0;
    end
    else if (~StallD)
    begin
        InstrD <= InstrF;
        PCD <= PCF;
        PCPlus4D <= PCPlus4F;
        isBranchD <= isBranchF;
        PredictedD <= PredictedF;
    end

// Register Memory logic
assign A1D = InstrD[19:15];
assign A2D = InstrD[24:20];
assign A3D = InstrD[11:7];

assign RD1D = (A1D != 0) ? RegFile[A1D] : 0;
assign RD2D = (A2D != 0) ? RegFile[A2D] : 0;

// Extend logic
always_comb
    case (ImmSrcD)
        2'b00: ImmExtD = {{21{InstrD[31]}}, InstrD[30:20]};
        2'b01: ImmExtD = {{21{InstrD[31]}}, InstrD[30:25], InstrD[11:7]};
        2'b10: ImmExtD = {{20{InstrD[31]}}, InstrD[7], InstrD[30:25], InstrD[11:8], 1'b0};
        default: ImmExtD = {{12{InstrD[31]}}, InstrD[19:12], InstrD[20], InstrD[30:21], 1'b0};
    endcase

// Decode --> Execute Register
always_ff @(posedge clk, posedge reset)
    if (reset | FlushE)
    begin
        RD1E <= 0;
        RD2E <= 0;
        PCE <= 0;
        ImmExtE <= 0;
        PCPlus4E <= 0;
        A3E <= 0;
        RegWriteE <= 0;
        ResultSrcE <= 0;
        MemWriteE <= 0;
        JumpE <= 0;
        BranchE <= 0;
        ALUControlE <= 0;
        ALUSrcE <= 0;
        A1E <= 0;
        A2E <= 0;
        isBranchE <= 0;
        PredictedE <= 0;
    end
    else if (~StallE)
    begin
        RD1E <= RD1D;
        RD2E <= RD2D;
        PCE <= PCD;
        ImmExtE <= ImmExtD;
        PCPlus4E <= PCPlus4D;
        A3E <= A3D;
        RegWriteE <= RegWriteD;
        ResultSrcE <= ResultSrcD;
        MemWriteE <= MemWriteD;
        JumpE <= JumpD;
        BranchE <= BranchD;
        ALUControlE <= ALUControlD;
        ALUSrcE <= ALUSrcD;
        A1E <= A1D;
        A2E <= A2D;
        isBranchE <= isBranchD;
        PredictedE <= PredictedD;
    end

// HAZARD
assign PCTargetE = PCE + ImmExtE;
// HAZARD

// ALU logic
assign SubtractE = ALUControlE[0];
assign ALUSumE = SrcAE + ALUSrcBE + SubtractE;

always_comb
    case (ForwardAE)
        2'b00: SrcAE = RD1E;
        2'b01: SrcAE = WD3W;
        2'b10: SrcAE = ALUResultM;
        default: SrcAE = RD1E;
    endcase

always_comb
    case (ForwardBE)
        2'b00: RD2EI = RD2E;
        2'b01: RD2EI = WD3W;
        2'b10: RD2EI = ALUResultM;
        default: RD2EI = RD2E;
    endcase

always_comb
    case (ALUSrcE)
        1'b0: SrcBE = RD2EI;
        default: SrcBE = ImmExtE;
    endcase

always_comb
    case (ALUControlE)
        3'b001: ALUSrcBE = ~SrcBE;
        3'b101: ALUSrcBE = ~SrcBE;
        default: ALUSrcBE = SrcBE;
    endcase

always_comb
    case (ALUControlE)
        3'b010: ALUResultE = SrcAE & ALUSrcBE;
        3'b011: ALUResultE = SrcAE | ALUSrcBE;
        3'b101: ALUResultE = ZeroExtE;
        default: ALUResultE = ALUSumE;
    endcase

// Overflow Defense
assign N1E = SubtractE ~^ (SrcAE[31] ^ SrcBE[31]);
assign N2E = SrcAE[31] ^ ALUSumE[31];
assign oVerflowE = N1E & N2E & ~ALUControlE[1];
assign SltResultE = oVerflowE ^ ALUSumE[31];
assign ZeroExtE = {{31{1'b0}}, SltResultE};

// Execute --> Memory Register
always_ff @(posedge clk, posedge reset)
    if (reset)
    begin
        ALUResultM <= 0;
        WDM <= 0;
        PCPlus4M <= 0;
        A3M <= 0;
        RegWriteM <= 0;
        ResultSrcM <= 0;
        MemWriteM <= 0;
    end
    else if (~StallM)
    begin
        ALUResultM <= ALUResultE;
        WDM <= RD2EI;
        PCPlus4M <= PCPlus4E;
        A3M <= A3E;
        RegWriteM <= RegWriteE;
        ResultSrcM <= ResultSrcE;
        MemWriteM <= MemWriteE;
    end

// Data Memory logic
always_comb
    case (ALUResultM[10])
        1'b1:
        begin
            case (ALUResultM[3:2])
            2'b00: RDM = 0;
            2'b01: RDM = {30'b0, RxReady, TxBusy};
            2'b10: RDM = {24'b0, RxData};
            2'b11: RDM = {20'b0, VGAReg};
            default: RDM = 0;
            endcase
        end
        1'b0:
        begin
            if (Hit) RDM = DCache[ALUResultM[7:4]][ALUResultM[3:2]];
        end
    endcase

// To not stall useless instructions, we have to make sure
// that a request was sent. These two signals only fire on
// lw and sw.
assign MemoryAccess = MemWriteM || (ResultSrcM == 2'b01);
assign Hit = Valid[ALUResultM[7:4]] && (Tag[ALUResultM[7:4]] == ALUResultM[9:8]);
assign Miss = MemoryAccess && ~Hit && ~ALUResultM[10];

// VGA logic
always_ff @(posedge clk, posedge reset)
begin
    if (reset) VGAReg <= 0;
    else if ((ALUResultM[3:2] == 2'b11) && (ALUResultM[10]) && (MemWriteM == 1'b1)) VGAReg <= WDM[11:0];
end

always_ff @(posedge clk, posedge reset)
    if (reset) RxReady <= 0;
    else if (RxValid) RxReady <= 1;
    else if (ALUResultM[10] && ALUResultM[3] && (ResultSrcM == 2'b01)) RxReady <= 0;

always_ff @(posedge clk)
    begin
        if (MemWriteM && ~ALUResultM[10])
        DataMem[ALUResultM[9:2]] <= WDM;
        if (MemWriteM && ~ALUResultM[10] && Hit)
        DCache[ALUResultM[7:4]][ALUResultM[3:2]] <= WDM;
    end

// UART Echo logic
assign TxSend = MemWriteM && ALUResultM[10] && (ALUResultM[3:2] == 2'b00);
assign TxByte = WDM[7:0];

// Memory --> Writeback Register
always_ff @(posedge clk, posedge reset)
    if (reset)
    begin
        RDW <= 0;
        ALUResultW <= 0;
        PCPlus4W <= 0;
        A3W <= 0;
        RegWriteW <= 0;
        ResultSrcW <= 0;
    end
    else if (~StallW)
    begin
        RDW <= RDM;
        ALUResultW <= ALUResultM;
        PCPlus4W <= PCPlus4M;
        A3W <= A3M;
        RegWriteW <= RegWriteM;
        ResultSrcW <= ResultSrcM;
    end

// End Mux logic
// HAZARD
always_comb
    case (ResultSrcW)
        2'b00: WD3W = ALUResultW;
        2'b01: WD3W = RDW;
        2'b10: WD3W = PCPlus4W;
        default: WD3W = ALUResultW;
    endcase

always_ff @(negedge clk)
    if (RegWriteW) RegFile[A3W] <= WD3W;
// HAZARD

// Hazard Unit logic
always_comb
begin
    if ((A1E == A3M) && RegWriteM && (A1E != 0)) ForwardAE = 2'b10;
    else if ((A1E == A3W) && RegWriteW && (A1E != 0)) ForwardAE = 2'b01;
    else ForwardAE = 2'b00;
end

always_comb
begin
    if ((A2E == A3M) && RegWriteM && (A2E != 0)) ForwardBE = 2'b10;
    else if ((A2E == A3W) && RegWriteW && (A2E != 0)) ForwardBE = 2'b01;
    else ForwardBE = 2'b00;
end

assign lwStall = ResultSrcE[0] & ((ReadsRS1 && (A1D == A3E)) | (ReadsRS2 & (A2D == A3E)));
assign StallF = lwStall || MemStall;
assign StallD = lwStall || MemStall;
assign StallE = MemStall;
assign StallM = MemStall;
assign FlushD = (PCSrcE == 2'b01) && ~MemStall;
assign FlushE = (lwStall || (PCSrcE == 2'b01)) && ~MemStall;
assign StallW = MemStall;
endmodule
