// clk and reset are the only pipeline dependencies
// TxByte is the outputted letter
// TxSend tells the transmitter to send the letter out
// TxBusy tells the processor that the last byte is still being processed
// Basically, if TxBusy is low, put the byte on TxByte and pulse TxSend

// RxData is the character that has arrived
// RxValid is the receiver saying the byte has arrived
// Because RxValid is only high for one cycle, RxReady catches it and holds onto it

// VGAReg is the background color, 4 red, 4 green, 4 blue
module pipelined(input logic clk, reset, RxValid, TxBusy, input logic [7:0] RxData, output logic TxSend, output logic [7:0] TxByte, output logic [11:0] VGAReg);

// Control Unit declarations
logic [6:0] Op; // signals the type of instruction
logic [2:0] Funct3; // signals the specific instruction inside the type
logic [1:0] ALUOp; // tells the ALU's function. 00 is used for lw, sw, and jal.
// 01 is used for beq. 10 is used for R-type and I-type ALU instructions
logic Funct7; // tells add apart from sub

// Decode Control
logic [2:0] ALUControlD; // 000 add, 001 sub, 010 and, 011 or, 101 slt
logic [1:0] ImmSrcD; // what shape is the immediate?
logic [1:0] ResultSrcD; // which way writeback comes from: ALU, memory, or PC+4
logic MemWriteD; // does this write to data memory?
logic ALUSrcD; // does the ALU's second input come from a register or the immediate
logic RegWriteD; // does this instruction write a result into a register?
logic BranchD; // is this a branch?
logic JumpD; // is this a jump?

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
logic [31:0] InstrMem [0:63]; // gives space for 64 instructions

// Register Memory declarations
logic [31:0] RegFile [31:0]; // declares the 32 registers

// Data Memory declarations
logic [31:0] DataMem [0:255]; // main memory consisting of 256 words

// Pipelined Register declarations
// Fetch
logic [31:0] PCFNext; // the next instruction
logic [31:0] PCF; // the program counter, holding the address of the instruction being fetched
logic [31:0] PCPlus4F; // the address of the next instruction in sequence
logic [31:0] InstrF; // the instruction read from instruction memory

// Decode
logic [31:0] InstrD, PCD, PCPlus4D;
logic [31:0] ImmExtD; // sign-extends the immediate that is baked into the instruction
logic [31:0] RD1D; // data read out of A1
logic [31:0] RD2D; // data read out of A2
logic [4:0] A1D; // address of the first source register
logic [4:0] A2D; // address of the second source register
logic [4:0] A3D; // address of the destination register

// Execute
logic [31:0] RD1E, RD2E, PCE, ImmExtE, PCPlus4E;
logic [31:0] PCTargetE; // branch destination
logic [31:0] ALUResultE; // FINAL ALU answer
logic [31:0] SrcAE; // first ALU input after mux
logic [31:0] SrcBE; // second ALU input after mux
logic [31:0] ALUSumE; // adder output
logic [31:0] ALUSrcBE; // takes SrcBE's value and optionally flips for subtraction
logic [31:0] ZeroExtE; // final result for signed comparison path for slt
logic [4:0] A3E;
logic SubtractE, N1E, N2E, oVerflowE, SltResultE; // used to compute signed comparison path for slt
// Memory
logic [31:0] PCPlus4M, ALUResultM;
logic [31:0] WDM;
logic [31:0] RDM;
logic [4:0] A3M;
// Writeback
logic [31:0] ALUResultW, PCPlus4W, RDW;
logic [31:0] WD3W; // the data being written back
logic [4:0] A3W;

// HAZARD Unit declarations
logic [31:0] RD2EI;
logic [4:0] A1E, A2E;
logic [1:0] ForwardAE, ForwardBE; // picks where each ALU input comes from. either
// the register file normally, or a result grabbed early out of Memory or Writeback
logic StallF, StallD, StallE, StallM, StallW; // freeze the labeled stage
logic FlushD, FlushE; // resets the stage to 0
logic lwStall; // pauses the pipeline for one cycle
logic ReadsRS1, ReadsRS2; // tells whether the source registers were read

// UART Echo declarations
logic RxReady;

// Branch Prediction declarations
logic isBranchF, isBranchD, isBranchE; // marks "this instruction is a branch"
logic MisPredict; // tells that the comparison came back wrong
logic PredictedF, PredictedD, PredictedE; // the guess that was made
logic [31:0] PCTargetF; // branch destination computed early
logic [1:0] BranchState [0:63]; // the actual predictor. 64 entries with 2 bits each
logic [1:0] BranchNextState; // what the predictor entry becomes after you find out if the branch went

// Memory Hierarchy declarations
logic Valid [0:7][0:1]; // says whether the slot holds an actual value. 8 sets of 2 ways
logic [2:0] Tag [0:7][0:1]; // records which chunk of memory is parked in each slot.
// 8 sets of 2 ways
logic [31:0] DCache [0:7][0:1][0:3]; // the actual cache data, consisting of 8 sets,
// 2 ways each, 4 words per way. 64 words total
logic LRU [0:7]; // one bit per set. tells which of the two ways was used last
logic CacheState, CacheNextState; // two state machines. sitting idle or fetching from slow mem
logic Hit0, Hit1; // tells whether way 0 matched or way 1 matched
logic Hit, Miss; // miss is if either hit0 or hit1 matched. miss is neither
logic Victim; // the way about to get evicted
logic MemoryAccess; // tells whether the instruction is a load or store
logic MemReady; // fires when MemCount hits 0
logic MemStall; // freezes the pipeline while a miss is being serviced
logic [4:0] MemCount; // counts down the 15 cycle penalty

// Control Unit logic
assign Op = InstrD[6:0]; // assigns Op to the first seven bits of Instr
assign Funct3 = InstrD[14:12]; // assigns Funct3 to bits 14:12 of Instr
assign Funct7 = InstrD[30]; // assigns Funct7 to bit 30 of Instr

// Main Decoder
// Based on the opcode, outputs 10 signals for the specific instruction
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
    // default lw
    default: {RegWriteD, ImmSrcD, ALUSrcD, MemWriteD, ResultSrcD, BranchD, ALUOp, JumpD, ReadsRS1, ReadsRS2} = 13'b0_00_0_0_00_0_00_0_1_0;
endcase

// ALU Decoder
always_comb
    case (ALUOp) // Decides whether further thinking is needed
        2'b00: ALUControlD = 3'b000; // just add
        2'b01: ALUControlD = 3'b001; // just subtract
        2'b10: // we need to figure out the operation
        begin
        case (Funct3) // all R-type and I-type ALU instructions share the same opcode.
        // Funct3 differentiates them
            3'b000: // can mean add, sub, or addi. needs another differentiator
            begin
                case ({Op[5], Funct7}) // cannot just use Funct7, also need bit 5 of opcode
                // due to addi/sub conflicts
                    2'b11: ALUControlD = 3'b001; // sub
                    default: ALUControlD = 3'b000; // add
                endcase
            end
            3'b010: ALUControlD = 3'b101; // slt
            3'b110: ALUControlD = 3'b011; // or
            3'b111: ALUControlD = 3'b010; // and
            default: ALUControlD = 3'b000;
        endcase
        end
        default: ALUControlD = 3'b000;
    endcase

// Zero and PCSrc Logic
// ZeroE asks if the ALUResult is 0 or not. This is important because beq works by
// subtracting the two source registers to determine if they're equal.
always_comb
    case (ALUResultE)
        32'b0: ZeroE = 1'b1;
        default: ZeroE = 1'b0;
    endcase

// If ZeroE and PredictedE match, MisPredict returns 0. If they differ, it returns 1
assign MisPredict = ZeroE ^ PredictedE;

// Determines where the PC goes next. A few things happen here
always_comb
begin
	if ((BranchE && MisPredict) | JumpE) PCSrcE = 2'b01; // signals that a mistake was made
	else if (isBranchF && PredictedF) PCSrcE = 2'b10; // makes a guess and branches off
	else PCSrcE = 2'b00; // normal operation
end

// Branch Prediction FSM
// Taken is represented by 0 while NotTaken is represented by 1. The reason we have
// two bits in the first place is to buy us a free mistake. We can still predict in
// the same direction without shifting the stance completely. Also, localparam is used
// over parameter so it cannot be changed from the outside
localparam StronglyTaken = 2'b00;
localparam WeaklyTaken = 2'b01;
localparam WeaklyNotTaken = 2'b10;
localparam StronglyNotTaken = 2'b11;

always_ff @(posedge clk, posedge reset)
    if (reset) // if reset, walks every entry and sets it to 0
        begin
            for (int i = 0; i < 64; ++i)
            begin
                BranchState[i] <= WeaklyTaken;
            end
        end
    else if (BranchE) BranchState[PCE[7:2]] <= BranchNextState; // only updates when
    // a branch is in Execute. PCE[7:2] is the index. The bottom two bits are alwayys
    // 00, so they're dropped. 6 bits gives 64 entries.

// the state machine. basically, if the branch is taken, you walk left towards WeaklyTaken
// and StronglyTaken. if the branch isn't taken, you walk right towards WeaklyNotTaken and
// StronglyNotTaken
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
localparam Idle = 1'b0; // the cache is answering normally
localparam Fetch = 1'b1; // something missed, we're waiting on slow memory

assign MemReady = (MemCount == 0); // fires when the countdown from 15 hits 0
assign Victim = ~LRU[ALUResultM[6:4]]; // finds the least recently used by indexing into
// LRU using 3 bits of ALUResult (giving 8 entries), then inverting

always_ff @(posedge clk, posedge reset)
    if (reset) // if reset, walks Valid and sets everything to 0
        begin
            CacheState <= Idle;
            for (int i = 0; i < 8; ++i)
                begin
                    LRU[i] <= 0;
                    for (int j = 0; j < 2; ++j)
                    begin
                        Valid[i][j] <= 0;
                    end
                end
        end
    else
    begin
        CacheState <= CacheNextState; // state register ticks

        if (MemoryAccess && Hit0) LRU[ALUResultM[6:4]] <= 0; // sets to 0 if way 0 hits
        if (MemoryAccess && Hit1) LRU[ALUResultM[6:4]] <= 1; // sets to 1 if way 1 hits

        if (CacheState == Fetch && MemReady) // when the state = fetch and timer has expired
        begin
            Valid[ALUResultM[6:4]][Victim] <= 1'b1; // the current slot is set to valid
            Tag[ALUResultM[6:4]][Victim] <= ALUResultM[9:7]; // sets the slot's tag
            LRU[ALUResultM[6:4]] <= Victim; // sets the slot as the most recent

            // stores data in all four words in the way
            DCache[ALUResultM[6:4]][Victim][0] <= DataMem[{ALUResultM[9:4], 2'b00}];
            DCache[ALUResultM[6:4]][Victim][1] <= DataMem[{ALUResultM[9:4], 2'b01}];
            DCache[ALUResultM[6:4]][Victim][2] <= DataMem[{ALUResultM[9:4], 2'b10}];
            DCache[ALUResultM[6:4]][Victim][3] <= DataMem[{ALUResultM[9:4], 2'b11}];
        end

        // if it's a write to memory, not a peripheral, and there was a hit, WDM
        // gets written into the DCache
        if (MemWriteM && ~ALUResultM[10] && Hit)
        DCache[ALUResultM[6:4]][Hit0 ? 1'b0 : 1'b1][ALUResultM[3:2]] <= WDM;
    end

always_comb
    case (CacheState)
        Idle:
        begin
            MemStall = Miss; // stalls in the SAME cycle to prevent a delay
            CacheNextState = Miss ? Fetch : Idle; // if miss, go to fetch. otherwise stay in idle
        end
        Fetch:
        begin
            MemStall = 1; // stalls the entire time while in fetch
            if (MemReady) CacheNextState = Idle; // once memory is ready, go to idlle
            else CacheNextState = Fetch; // otherwise stay in fetch
        end
    endcase

// Program Counter logic
always_ff @(posedge clk, posedge reset)
    if (reset) PCF <= 0; // if reset, set PCF to 0
    else if (~StallF) PCF <= PCFNext; // if the register is NOT stalled, proceed

assign PCPlus4F = PCF + 4; // computes the next address in sequence
// early computes the branch address to be usable in Fetch
assign PCTargetF = PCF + {{20{InstrF[31]}}, InstrF[7], InstrF[30:25], InstrF[11:8], 1'b0};

// mux on PCFNext
always_comb
    case (PCSrcE)
        2'b00: PCFNext = PCPlus4F; // standard sequential address, just +4
        2'b01: // a mistake was made or jal
        begin
            if (isBranchE == 1'b1 && ZeroE == 1'b0) PCFNext = PCPlus4E; // redirects the PC to the actual branch address
            else PCFNext = PCTargetE; // otherwise redirect to jal jump address
        end
        2'b10: PCFNext = PCTargetF; // if a branch is predicted, go to the early branch address
        default: PCFNext = PCPlus4F;
    endcase

// Instruction Memory logic
initial $readmemh("memory.hex", InstrMem); // reads instructions from a file and places them in InstrMem
assign InstrF = InstrMem[PCF[7:2]]; // indexes into InstrMem with 6 bits = 64 entries

// Branch Prediction logic
always_comb
begin
	if (InstrF[6:0] == 7'b1100011) isBranchF = 1; // predicts a branch based off the opcode
	else isBranchF = 0; // otherwise not a branch
end

assign PredictedF = ~BranchState[PCF[7:2]][1]; // indexes into the two-bit confidence value, grabbing the
// starting 1 and 0. It must be inverted because in this encoding, Taken is 0 and NotTaken is 1.

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
assign A1D = InstrD[19:15]; // first source register
assign A2D = InstrD[24:20]; // second source register
assign A3D = InstrD[11:7]; // destination register

assign RD1D = (A1D != 0) ? RegFile[A1D] : 0; // x0 is always zero. Basically, if A1 = 0, return 0.
// otherwise, index into RegFile with A1D, grab that register's contents, and store them in RD1D.
// Same thing for RD2D.
assign RD2D = (A2D != 0) ? RegFile[A2D] : 0;

// Extend logic
always_comb
    case (ImmSrcD)
        2'b00: ImmExtD = {{21{InstrD[31]}}, InstrD[30:20]}; // I-type: lw, addi, andi, ori, slti
        2'b01: ImmExtD = {{21{InstrD[31]}}, InstrD[30:25], InstrD[11:7]}; // S-type: sw
        2'b10: ImmExtD = {{20{InstrD[31]}}, InstrD[7], InstrD[30:25], InstrD[11:8], 1'b0}; // B-type: beq
        default: ImmExtD = {{12{InstrD[31]}}, InstrD[19:12], InstrD[20], InstrD[30:21], 1'b0}; // J-type: jal
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

// computes the branch destination, PC plus offset
assign PCTargetE = PCE + ImmExtE;

// ALU logic
// a - b = a + (~b) + 1
// SubtractE could be assigned to 1, but ALUControlE[0] is 1 for sub and slt. And
// that would require additional logic. ALUControl[E] is 1 for computation that matters
// and 0 for computation that doesn't use it.
assign SubtractE = ALUControlE[0];
// Adder sum. First input + second input + 1 or 0
assign ALUSumE = SrcAE + ALUSrcBE + SubtractE;

// picks input A
always_comb
    case (ForwardAE)
        2'b00: SrcAE = RD1E; // register file, normal case
        2'b01: SrcAE = WD3W; // grab it from Writeback
        2'b10: SrcAE = ALUResultM; // grab it from Memory
        default: SrcAE = RD1E;
    endcase

// picks input B
always_comb
    case (ForwardBE)
        2'b00: RD2EI = RD2E; // register file, normal case
        2'b01: RD2EI = WD3W; // grab it from Writeback
        2'b10: RD2EI = ALUResultM; // grab it from Memory
        default: RD2EI = RD2E;
    endcase

// stores need their immediates to compute the address
always_comb
    case (ALUSrcE)
        1'b0: SrcBE = RD2EI; // picks RD2EI, as described before
        default: SrcBE = ImmExtE; // otherwise, grab the immediate
    endcase

always_comb
    case (ALUControlE)
    // For sub and slt we need subtraction, so we invert b, which is ALUSrcBE
        3'b001: ALUSrcBE = ~SrcBE; // sub
        3'b101: ALUSrcBE = ~SrcBE; // slt
        default: ALUSrcBE = SrcBE; // otherwise resume normal computation
    endcase

always_comb
    case (ALUControlE)
        3'b010: ALUResultE = SrcAE & ALUSrcBE; // and operation
        3'b011: ALUResultE = SrcAE | ALUSrcBE; // or operation
        3'b101: ALUResultE = ZeroExtE; // slt operation
        default: ALUResultE = ALUSumE; // add/sub operation
    endcase

// Overflow Defense
assign N1E = SubtractE ~^ (SrcAE[31] ^ SrcBE[31]); // could this overflow, based on the operand signs
assign N2E = SrcAE[31] ^ ALUSumE[31]; // did the answer's sign come out wrong
assign oVerflowE = N1E & N2E & ~ALUControlE[1]; // determines if it overflowed
assign SltResultE = oVerflowE ^ ALUSumE[31]; // the sign bit, flipped if it lied
assign ZeroExtE = {{31{1'b0}}, SltResultE}; // that one bit padded out to 32

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
    case (ALUResultM[10]) // tells whether this is an instruction or not
        1'b1: // this IS a peripheral
        begin
            case (ALUResultM[3:2]) // picks the register
            2'b00: RDM = 0; // 0 because 0x400 is the transmit register
            2'b01: RDM = {30'b0, RxReady, TxBusy}; // packages RxReady and TxBusy
            2'b10: RDM = {24'b0, RxData}; // same idea, packages the byte
            2'b11: RDM = {20'b0, VGAReg}; // for the VGA Pattern Generator
            default: RDM = 0;
            endcase
        end
        1'b0: // this is NOT a peripheral
        begin
            // did way 0 hit, and if not use way 1. if neither hit, way 1's contents
            // are handed back, which is garbage. A miss raises MemStall anyway, making
            // sure nothing latches onto the garbage
            RDM = Hit0 ? DCache[ALUResultM[6:4]][0][ALUResultM[3:2]]
            : DCache[ALUResultM[6:4]][1][ALUResultM[3:2]];
        end
    endcase

// To not stall useless instructions, we have to make sure
// that a request was sent. These two signals only fire on
// lw and sw.
assign MemoryAccess = MemWriteM || (ResultSrcM == 2'b01);

// To confirm a hit, we need to make sure Valid is high so that we know the slot
// holds something real. We also need to be sure that the tag in the slot matches
// the tag of ALUResultM
assign Hit0 = Valid[ALUResultM[6:4]][0] && (Tag[ALUResultM[6:4]][0] == ALUResultM[9:7]);
assign Hit1 = Valid[ALUResultM[6:4]][1] && (Tag[ALUResultM[6:4]][1] == ALUResultM[9:7]);
// An actual hit is true if either way hits.
assign Hit = Hit0 || Hit1;
// To miss, a few things need to be confirmed. It has to be a lw or sw instruction,
// it cannot be a hit, it cannot be a peripheral, and it's a load specifically.
assign Miss = MemoryAccess && ~Hit && ~ALUResultM[10] && (ResultSrcM == 2'b01);

// Slow Memory logic
always_ff @(posedge clk, posedge reset)
    if (reset) MemCount <= 0;
    // Purely to test the D-cache. We create a 15-cycle latency by firing MemReady
    // every time MemCount == 0, and we initially set MemCount to 0 and count down
    // by 1 every clk cycle.
    else if (CacheState == Idle && Miss) MemCount <= 15;
    else if (CacheState == Fetch) MemCount <= MemCount - 1;

// VGA logic
always_ff @(posedge clk, posedge reset)
begin
    if (reset) VGAReg <= 0;
    // if it's the fourth peripheral slot, it IS a peripheral, and this is a store
    else if ((ALUResultM[3:2] == 2'b11) && (ALUResultM[10]) && (MemWriteM == 1'b1)) VGAReg <= WDM[11:0];
end

always_ff @(posedge clk, posedge reset)
    if (reset) RxReady <= 0;
    else if (RxValid) RxReady <= 1;
    // if it IS a peripheral, if it's the third peripheral slot, and it's a load
    else if (ALUResultM[10] && ALUResultM[3] && (ResultSrcM == 2'b01)) RxReady <= 0;

always_ff @(posedge clk)
    begin
        // if it's a write to memory and not a peripheral, DataMem indexed with
        // 7 bits gets WDM
        if (MemWriteM && ~ALUResultM[10])
        DataMem[ALUResultM[9:2]] <= WDM;
    end

// UART Echo logic
// if it's a write to memory, it is a peripheral, and it's the first peripheral slot
assign TxSend = MemWriteM && ALUResultM[10] && (ALUResultM[3:2] == 2'b00);
// assign the uart byte to whatever is in WDM[7:0]
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
//
always_comb
    case (ResultSrcW)
        2'b00: WD3W = ALUResultW; // writes ALUResult back
        2'b01: WD3W = RDW; // writes the read data back
        2'b10: WD3W = PCPlus4W; // writes next sequential address back
        default: WD3W = ALUResultW;
    endcase

always_ff @(negedge clk)
    // writes on the negative edge of clk because instructions in decode read the
    // register file combinationally. If this was written on the posedge, it would
    // read stale data.S
    if (RegWriteW) RegFile[A3W] <= WD3W;

// Hazard Unit logic
always_comb
begin
    // A1E is the source and A3M is the destination. If they match and the instruction
    // is writing, forward its value.
    if ((A1E == A3M) && RegWriteM && (A1E != 0)) ForwardAE = 2'b10;
    // Same check for writeback
    else if ((A1E == A3W) && RegWriteW && (A1E != 0)) ForwardAE = 2'b01;
    // if nothing, use the register file
    else ForwardAE = 2'b00;
end

always_comb
begin
    // same checks for A2
    if ((A2E == A3M) && RegWriteM && (A2E != 0)) ForwardBE = 2'b10;
    else if ((A2E == A3W) && RegWriteW && (A2E != 0)) ForwardBE = 2'b01;
    else ForwardBE = 2'b00;
end

// stall and flush logic
assign lwStall = ResultSrcE[0] & ((ReadsRS1 && (A1D == A3E)) | (ReadsRS2 & (A2D == A3E)));
assign StallF = lwStall || MemStall;
assign StallD = lwStall || MemStall;
assign StallE = MemStall;
assign StallM = MemStall;
assign StallW = MemStall;
assign FlushD = (PCSrcE == 2'b01) && ~MemStall;
assign FlushE = (lwStall || (PCSrcE == 2'b01)) && ~MemStall;

endmodule
