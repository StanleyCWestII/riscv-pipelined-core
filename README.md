# riscv-pipelined-core

---

## 1. Overview

riscv-pipelined-core is a 5-stage pipelined RV32I core that implements a 2-bit branch predictor, a branch target buffer, a return address stack, a write-back memory cache, an instruction cache, a UART echo, and a VGA pattern generator. It is written in SystemVerilog and runs on the Nexys A7-100T FPGA.

| Claim | Number |
|---|---|
| Regression | 176/176 checks, 22 programs |
| rv32ui | 40/40 tests, excluding fence_i and ma_data; custom bare metal environment |
| Branch Prediction | T8: 291 cycles (always-taken) --> 174 cycles, 40.2% reduction |
| Return Prediction | T21: 97 --> 91 cycles, 6.2% fewer cycles |
| I-cache | 2503 --> 174 cycles, 98.6% fetch hit rate, 4.99-14.39x speedup |
| D-cache | 3.23-7.24x speedup, 134/134 write-back tests |
| Associativity | conflict benchmark 0% --> 96.9% hit rate |
| UART Echo | 760/760 bytes returned, zero errors |
| VGA Simulation | Standalone timing checks pass, integration 7/7 |
| Compiled C | Both programs pass: 77 and 124 cycles |

---

## 2. Quick Start

### 2a. Key

This section is to help navigate the README:

| Section | What It's About | Location |
|---|---|---|
| 2b | Makefile, running all testbenches | 55-71 |
| 2c | Vivado setup | 73-81 |
| 3a | In-depth look into the pipeline | 93-198 |
| 3b | Link to branch predictor file | 202 |
| 3c | In-depth look into the I-cache and D-cache | 204-282 |
| 3d | In-depth look into the UART and VGA | 284-329 |
| 3e | List of all supported instructions | 331-344 |
| 4a | Small summary of my verification methodology | 350-354 |
| 4b | All 176/176 regressions | 356-382 |
| 4c | Summary of unverified components | 384-391 |
| 4e | Details on issues found from Vivado | 393-467 |
| 5a | Summary of branch prediction cycle improvement | 473-493 |
| 5b | Summary of D-cache cycle improvement | 495-513 |
| 5c | Summary of I-cache cycle improvement | 515-527 |
| 5d | Details the organization of I-cache and D-cache | 528-545 |
| 5e | Associativity benchmarks for B4 | 547-567 |
| 5f | Timing and critical path of the processor | 570-605 |
| 6a | ASCII block diagram for the processor | 611-721 |
| 6b | Memory maps for UART and VGA | 724-735 |
| 6c | Details FPGA resources used for the processor | 737-749 |
| 7 | Details the repo layout | 757-763 |
| 8 | Limitations with the current design | 771-776 |
| 9 | Authorship table for the repo | 780-802 |

### 2b. Simulation

```
make                # 176-check regression
make isa            # 40/40 rv32ui; fence_i and ma_data excluded
make ctest          # main returned 10 in 77 cycles
make ctest-data     # main returned 31 in 124 cycles
make cache          # D-cache benchmarks, 3.23-7.24x
make associativity  # Associativity benchmarks for B4
make icache         # I-cache benchmarks, 4.99-14.39x
make writeback      # 134/134 benchmark for D-cache
make branch         # 176/176 benchmark for branch prediction
make vga            # VGA timing benchmark
make top            # core drives VGA, integration
```

iverilog is required along with Python 3 for asm.py. The C and ISA tests require riscv64-elf-gcc and riscv64-elf-objcopy. Disassembly uses riscv64-elf-objdump.

### 2c. Hardware

Tested on a Nexys A7-100T, part xc7a100tcsg324-1. Assemble a program first, since the bitstream contains whatever is in memory.hex at synthesis time:

```
python3 asm.py uart/echo.s memory.hex   # or vga/vgatest.s
```

After assembling the hex file, open Vivado and run the following in its Tcl Console. Replace the path with your repo location:

```
source {/full/path/to/riscv-pipelined-core/fpga/build.tcl}
```

The echo demo needs no external hardware. Channel B of the FT2232H is a USB serial bridge wired to UART_TXD_IN and UART_RXD_OUT. Any 115200 8N1 terminal will do.

---

## 3. What This Project Is

### 3a. The Pipeline and Hazard Unit

The processor is split into the Control Unit, Pipeline, Hazard Unit, and extras (peripherals, branch prediction, cache). 

#### The Control Unit

The Control Unit is split into the OpCode Decoder and ALU Decoder. The OpCode decoder takes OpD (the opcode in the decode stage), and assigns ten different signals with varying values:

1. `RegWriteD`: one-bit, tells if the instruction writes to the register file.
2. `ImmSrcD`: three-bit, tells where to grab the immediate from in the instruction.
3. `ALUSrcD`: one-bit, tells whether the ALU's second input comes from a register or the immediate
4. `MemWriteD`: one-bit, tells if the instruction writes to data memory.
5. `ResultSrcD`: two-bit, tells whether the write-back to the register file comes from the ALU, PC + 4, loaded data, or, in the case of environment calls, `TrapCause`.
6. `BranchD`: carries whether the instruction is a branch or not.
7. `ALUOp`: partly decides the value of ALUControlD.
8. `JumpD`: carries whether the instruction is a jump or not.
9. `ReadsRS1`: carries whether the instruction reads the first source register.
10. `ReadsRS2`: carries whether the instruction reads the second source register.

The ALU Decoder determines the value of `ALUControlD` through several signals. It initially decodes off of `ALUOp`, where 00 is add, 01 is subtract, and 10 is another operation that must be solved. From `ALUOp` = 10, we decode off of `Funct3D`. 001 is sll, 010 is slt, 011 is sltu, 100 is xor, 110 is or, and 111 is and. `Funct3D` = 000 and 101 requires further decoding. 

From 000, we decode off of the sixth bit of `OpD` concatenated with the sixth bit of `Funct7`. For this pairing, 00 represents add while 11 is subtract. From 101, we decode purely off of `Funct7`. 0000000 means srl and 0100000 means sra.

#### The Pipeline

The Pipeline is split into five stages: Fetch, Decode, Execute, Memory, Writeback. We'll start with Fetch.

Also, all signals ending in F belong to Fetch. All signals ending in D belong to Decode. All signals ending in E belong to Execute. All signals ending in M belong to Memory. All signals ending in W belong to Writeback.

##### Fetch

Fetch includes the program counter (PC), instruction memory, a hold register to make up for memory delay, an adder, I-cache, and additional cache/branch logic which will be discussed in 3b and 3c. 

The program counter is a register that holds the memory address of the next instruction. Every clock cycle (unless `Reset` or `StallF` is asserted), it updates. `PCF` holds the newest fetch request while `PCHold` holds the address matching `InstrF`.

Instruction memory is 64 KiB and reads on the clock. However, because the initial call is delayed, RetInstr forces Decode to be flushed until the first instruction arrives. 

Fetch also contains an adder to compute the next sequential address, PC + 4.

##### Decode

Decode includes the Register Memory, extender, and additional logic for ebreak and ecall. 

The register memory is a block of thirty-two registers each 32-bit. By RISC-V documentation, these registers extend x0-x31, where x0 is pinned to zero. `InstrD` picks out the first and second source registers along with the destination register, labeled `A1D`, `A2D`, and `A3D` respectively. Using those register signals, we then index into the register memory to grab the actual values sitting in each register: `RD1D` and `RD2D`. These signals are sent to Execute.

The extender takes `ImmSrcD`, which varies by opcode, and decides how to decode and extend the immediate out of the instruction. Because different types store their immediates differently, some stitching has to be done. 000 decodes for I-type, 001 decodes for S-type, 010 decodes for B-type, 011 decodes for J-type, and 100 decodes for U-type.

ecall and ebreak detection sits in Decode because they detect off of the opcode currently in Decode. We then detect off of `ImmExtD` to distinguish between ecall and ebreak and set their corresponding signals, `StallPC` and `TrapCause`.

##### Execute

Execute includes the processor's ALU, multiplexers to decide the ALU's input, overflow detection, and additional logic for jumps and branches.

There's a naming mismatch, but just know that the ALU's upper input is `SrcAE` and the ALU's bottom input is `ALUSrcBE`. The first multiplexer decodes off of `ForwardAE`, a hazard unit signal, and decides whether `SrcAE` comes from the register file, from the writeback stage, from `ALUResultM`, or from the program counter.

The second mux chooses `RD2EI`, which is an intermediate signal for `ALUSrcBE`. It decodes off of `ForwardBE`, and chooses either from the register file, writeback, or `ALUResultM`.

The third mux chooses `SrcBE`, another intermediate signal for `ALUSrcBE`. It decodes off of `ALUSrcE` and basically chooses whether the ALU's second input comes from the previously mentioned `RD2EI` or the sign-extended immediate, `ImmExtE`.

The fourth and final ALU mux then determines `ALUSrcBE`. This mux exists because, for sub and slt operations, `SrcBE` is required to be inverted. It decodes off of `ALUControlE`. 

The ALU is mainly composed of adders and exists to handle all of the processor's arithmetic operations. Based off of ALUControlE, it performs ten different arithmetic operations.

00010 assumes and, 00011 assumes or, 00101 assumes slt, 00110 assumes xor, 00111 assumes sll, 01000 assumes srl, 01001 assumes sra, 01011 assumes sltu, and the default is set to add/sub.

The ALU also contains overflow detection for slt using a multitude of intermediate signals. It first determines whether the operation could overflow based on the operand signs. It then determines whether the answer's sign actually came out wrong, and then uses both pieces of information to determine if the answer overflowed. If it did overflow, the sign bit is flipped and then becomes the low bit of the slt result.

Execute contains one additional mux for branches. Based off of `Funct3E`, it decodes operations for beq, bne, blt, bge, bltu, and bgeu. If any of these branches fire, `BranchTaken` is set to 1, which is then used for further branch operations down the line.

##### Memory

Memory includes the data memory, D-cache, slow memory, and some UART Echo/VGA logic. 

Unlike the instruction memory, which is one 64 KiB block, the data memory is split into four chunks of 16 KiB, `DataMem0`, `DataMem1`, `DataMem2`, and `DataMem3`. This is merely for speed, so it can load four words at a time instead of one.

The first check on data memory comes from `ALUResultM[16]`. This bit is set for the UART Echo and VGA generator, and otherwise zero for regular operation. If the peripheral bit is set, the mux then decodes off of `ALUResultM[3:2]`, which picks the register that the peripheral data is read into. 00 sets `RDM`, which is a storage for data loaded from memory, to 0. This is because 0x10000 is the transmit register. 01 packages `RDM` with `RxReady` and `TxBusy` for the UART Echo. 10 packages `RDM` with `RxData`, which is the byte assembled by the UART Echo. 11 packages RDM with all RGB bits for the VGA generator.

If the instruction is not a peripheral, `RDM` then reads from the D-cache. From that, the mux decodes off of `ALUResultM[1:0]` to decide which byte out of `RDM` to load from. This is meant for lb, lbu, lh, lhu, and lw. 

On a cache hit for sb, sh, or sw, they update the D-cache and mark it dirty. On a miss, they write to main memory and trigger a cache-line fill.

The slow memory logic exists as added modeled memory wait. By imposing a 15-cycle latency after every cache miss, we can record stalls, cache fills, and the benefits of hits. The actual logic is simple: if we're in the fetch stage of the cache FSM, count down from 15.

The VGA block writes the bottom twelve bits of `WDM`, which holds the RGB values, into `VGAReg`, which leaves the processor as output.

The UART block sets `RxReady` when a byte arrives and clears it when the byte is loaded from memory. It also assigns `TxByte` with the bottom eight bits of `WDM`, and sets `TxSend` when the instruction is a write to memory, a peripheral, and it's the first peripheral slot.

##### Writeback

Writeback is the lightest stage and only contains the final end multiplexer for writing back to the destination register. It decodes off of `ResultSrcW`. 00 sets `WD3W`, which holds the returning value, to ALUResultW. 10 sets `WD3W` to PCPlus4W. 11 sets `WD3W` to TrapCause for environmental calls. 01 decodes off of `Funct3W` and is meant for loads. 000 is for lb, 001 is for lh, 010 is for lw, 100 is for lbu, and 101 is for lhu. 

The final write into the destination register is on the negative edge of the clock, as instructions in decode read the register file combinationally. Writing on the positive edge would read stale data. In `RegFile[A3W]`, A3W selects which register.

#### The Hazard Unit

The Hazard Unit makes use of forwarding, flushing, and stalling to bypass typical pipelining errors. 

Forwarding is decided by equality checks on the source and destination registers using the control signals ForwardAE and ForwardBE. The instruction in the Memory stage is checked before the Writeback stage, because it holds the newer value. x0 is checked to prevent forwarding a false value.

Stalls are handled by eleven different signals: `lwStall`, `StallF`, `StallD`, `StallE`, `StallM`, `StallW`, `DMemStall`, `IMemStall`, `StallPC`, `EmptyPipeline`, and `StallBreak`.

`lwStall` fires when decode needs a register that the load in Execute will produce. `DMemStall` and `IMemStall` fire when waiting for a cache miss to finish. `StallPC` fires when decode contains a system instruction, such as ecall or ebreak. `EmptyPipeline` fires when there are zero valid instructions in Execute, Memory, or Writeback (which is determined from each pipeline's valid signal, set or reset inside the pipeline registers). `StallBreak` fires when a terminal trap has been recorded and EmptyPipeline is true. `StallF` fires on any cache wait, `lwStall`, `StallPC`, `StallBreak`, or recorded trap. `StallD` is similar to `StallF` except `StallPC` doesn't hold it. `StallE`, `StallM`, and `StallW` all fire on cache waits or `StallBreak`.

Flushes are only handled by two signals: `FlushD` and `FlushE`.

`FlushD` fires when Execute corrects a branch/jump prediction while neither cache is waiting, or `StallPC`, or instruction memory hasn't returned an instruction. `FlushE` fires on `lwStall` when both DMemStall and IMemStall are zero, or a prediction correction while neither cache is waiting, or `StallPC`.

### 3b. Branch Predictor, BTB, and RAS 

The branch prediction logic has its own dedicated file at [BRANCH_PREDICTOR.md](BRANCH_PREDICTOR.md). It contains a deep dive into the predictor, BTB, and RAS along with all their dedicated benchmarks.

### 3c. Caches

#### I-Cache

The I-cache consists of 8 sets, 1 way, and 8 words per line. It is 64 words in total. Its companion signals are `IValid`, which is 1-bit, 8 sets, and 1 way. It says whether a line contains any usable instructions. `ITag`, also 8 set, 1 way, makes up whatever bits are left after set and word indexing. In this case, it is 8 bits. The purpose of the tag is to identify which part of instruction memory the line came from. `IHit` flags a cache hit, `IMiss` flags a cache miss. `IMemReady`, `IMemStall`, and `IMemCount` are all slow memory declarations. The I-cache also has its own FSM, with two states: IIdle and IFetch. IIdle is the cache's default state. It enters IFetch whenever a cache miss is detected, which causes the cache to begin fetching the instruction from instruction memory.

`PCF` supplies the requested instruction's address:

- `PCF[7:5]` selects one of the eight sets.
- `PCF[15:8]` is compared with that set's stored tag.
- `PCF[4:2]` selects one of the eight words within the line.
- `PCF[1:0]` is unused because instructions are four-byte aligned.

The I-cache is direct-mapped, so each address only has one available cache location.

For cache hits, IHit looks at two things: whether `IValid[PCF[7:5]]` is set, and whether `ITag[PCF[7:5]]` matches `PCF[15:8]`.

For cache misses, IMiss looks at two things: whether there is no hit and whether the cache is in IIdle, its normal lookup state. Once a miss is detected, IMemStall is asserted, state moves to IFetch, and IMemCount is loaded with 15.

While in IFetch, the cache copies eight consecutive words from `InstrMem` into the selected set, stores `PCF[15:8]` in its tag, and sets its valid bit. From here, `IMemCount` counts down during IFetch. When it reaches zero, IMemReady asserts and moves state to IIdle. After returning to IIdle, the filled line produces a hit, the I-cache stall clears, and Fetch can resume if no other stall remains.

A miss replaces the line already occupying the selected set. There is no replacement policy because each set only has one way. 

#### D-Cache

The D-cache consists of 8 sets, 4 ways, and 16 words per line. It is 512 words in total, write-back, and write-allocate. Its companion signals are `DValid`, which is 1 bit, 8 sets, and 4 ways. It says whether a line holds usable data. `DTag` is 7 bits, 8 sets, and 4 ways. It identifies which part of data memory the line came from. `DDirty` is 1 bit, 8 sets, and 4 ways. It determines whether a cache line has been modified by a store. `LRU` is 3 bits and 8 sets. It is used for the cache replacement policy, and approximates the replacement order. `Victim` is 2 bits and holds the way which is soon to be evicted. `MemoryAccess` determines whether an instruction is a load or store. `Beat` is 2 bit and selects which four words get transferred during a cache fill. `HitWay` identifies which of the four ways match the requested address. The D-cache also has its own `DHit` signal, which fires if any of the way-specific hit signals, `DHit0`, `DHit1`, `DHit2`, or `DHit3` return true. `DMiss` fires on a load or store when there is no cache hit and the instruction is not a peripheral. Like the I-cache, the D-cache has its own slow memory declarations.

For the D-cache, `ALUResultM` supplies the address: 

- `ALUResultM[16]` selects peripherals.
- `ALUResultM[8:6]` selects one of eight sets.
- `ALUResultM[15:9]` is compared against the four stored tags.
- `ALUResultM[5:2]` selects one of sixteen words.
- `ALUResultM[1:0]` selects bytes within that word for smaller loads and stores.

A hit, represented by `DHit`, looks at the four way-specific hit signals. `DHit0` through `DHit3` check whether each way is valid and if its tag matches the requested address. If any one of them are true, `DHit` is asserted.

`HitWay` encodes each way for indexing later on. If `DHit0` is true, `HitWay` is 00. If `DHit1` is true, `HitWay` is 01. If `DHit2` is true, `HitWay` is 10. If `DHit3` is true, `HitWay` is 11. 

Whichever way hit then moves its word into `RDM`. For byte and halfword loads, `ALUResultM[1:0]` selects the requested portion, which is zero- or sign-extended. The data then proceeds to Writeback and the destination register.

When the instruction is a store, targets ordinary memory, and hits:

- `WDM` supplies the value to `DCache`.
- `HitWay` selects the matching way.
- `ALUResultM[5:2]` selects the word.
- `Funct3M` selects byte, halfword, or full-word storage.
- The line's `DDirty` bit becomes one.

Main memory is not updated. The new values sit in D-cache for now. Main memory is only updated on a miss, which goes as follows:

First, `DMiss` asserts for a load or store with no matching line. While in DIdle, that immediately asserts `DMemStall`. The cache enters DFetch and loads `DMemCount` with 15. The stall holds the entire pipeline, and once the countdown is finished, `DMemReady` is asserted.

From here, `Victim` selects the way to replace using tree-based pseudo-LRU, an approximation of least recently used. LRU works off of these three bits:

- `[2]`: which pair was used last, ways 0-1 or ways 2-3.
- `[1]`: which way was used last within ways 0-1.
- `[0]`: which way was used last within ways 2-3.

Replacement chooses the opposite pair, then the opposite way within that pair. Hits update those bits. Completing a fill marks the filled way as recently used.

Write-back requires writing soon-to-be replaced data back to data memory. Once `DMemReady` is asserted, `Beat` steps through four transfers, each transfer reading one word from each of the four data memory banks into the cache If the victim is dirty, that same clock also writes its four old words back to main memory. The write-back address uses the victim's stored tag. The incoming read uses the requested address. Write-back and refill are performed together, four words per clock.

A store miss also writes `WDM` directly into the selected data memory bank:

- `ALUResultM[3:2]` selects the bank.
- `ALUResultM[15:4]` selects its row.
- The store size determines which bytes change.

Meanwhile, the miss logic fills the requested cache line. Once the line is installed, the held store becomes a hit and updates the cache through the normal store-hit logic, making it dirty. This is why the cache is write-allocate with a direct memory write on misses, rather than write-through.

On the final transfer, the cache:

- Sets the filled line's valid bit.
- Stores the new tag.
- Clears its dirty bit.
- Updates replacement information.
- Returns to DIdle.
- Beat wraps back to zero.

### 3d. Peripherals

Right now, the only supported I/O for the processor is a UART Echo and VGA Pattern Generator.

#### UART Echo

The UART Echo is split between `transmitter.sv`, `receiver.sv`, `top.sv`, and `pipelined.sv`.

From `top.sv`, the receiver assembles the byte, the processor reads it, the echo program writes it to the transmitter, and the transmitter sends it back to the computer.

From `receiver.sv`, `Rx` comes from outside the FPGA and isn't synchronized with the clock. To get around this, `Sync1` samples `Rx`, and `Sync2` samples `Sync1`. This is to reduce metastability.

The wire sits high at default. When Sync2 goes low while `~Busy`, the receiver treats it as the beginning of a byte and sets `Busy`. 

At a 100 MHz board clock and 115200 bits per second, each serial bit lasts approximately 868 clock cycles. `Count` measures the clocks between samples. `Index` selects the incoming data bit. `Storage[Index]` holds the sampled bit. The retained first data sample takes 1.5 bit periods using `Count == 1301`, which skips sampling on the edge of the bit period. This is to prevent sampling bit transitions. After this, we use `Count == 867` for the next bit periods.

Bits arrive lowest bit first. `Data` continuously reflects `Storage`. After sampling bit seven, `Valid` pulses for one cycle.

From `pipelined.sv`, `RxData` carries the byte from the receiver as input logic. `RxValid` is the receiver's one-clock notification. `RxReady` remembers that notification until software reads the byte.

The program loads the status register at 0x10004 and checks `RxReady`. When ready, it reads the byte at 0x10008, which clears the flag. However, there is no queue of received bytes. `RxReady` signals that the byte is ready but does not store extra copies of it.

From `pipelined.sv` and `uart\echo.s`, the program checks `TxBusy` until the transmitter module is available, then stores the received byte to 0x10000. That store places `WDM[7:0]` on `TxByte` and asserts `TxSend`.

From `transmitter.sv` and `top.sv`, the top module constructs a 10-bit payload: start bit 0, eight data bits, and stop bit 1. When `Send` is asserted and `Busy` is clear, the transmitter captures the frame in `InputNext`. `Count` holds each bit for 868 clocks. `Index` advances through the ten payload bits, and `tx` outputs `InputNext[Index]`. After the final bit, `Busy` clears and `tx` returns to its idle-high value.

#### VGA Pattern Generator

The VGA generator is split between `vgagenerator.sv`, `pipelined.sv`, and `top.sv`.

From `vgagenerator.sv`, the two-bit `clkEnable` counter cycles through four values, and `Ready` asserts when it reaches three. This advances the screen position once every four clocks, which comes out to 25 million pixel positions per second.

`Horizontal` counts positions across a line. `Vertical` counts lines down the frame. Every `Ready` advances `Horizontal`. At the end of a line, `Horizontal` returns to zero and `Vertical` advances. At the end of the frame, both wrap around. The total is 800 positions * 525 lines, and the visible area is 640 x 480.

`Hsync` and `Vsync` tell the monitor where lines and frames align. Each direction includes:

- The visible picture.
- A front porch, an interval before the synchronization pulse.
- The synchronization pulse.
- A back porch, an interval after the pulse.

`VideoOn` is true only inside the 640 x 480 area. Outside it, the generator outputs black. The 25 MHz pixel rate makes the refresh rate approximately 59.52 Hz.

The visible width is divided into eight bars, each 80 pixels wide. The first seven are fixed: white, yellow, cyan, green, magenta, red, and blue. The eighth uses `BgColor`. `Red`, `Green`, and `Blue` each have four bits, making twelve color bits total. The pattern is calculated directly from `Horizontal`.

From `pipelined.sv` and `top.sv`, a program stores a color to 0x1000C. The processor copies `WDM[11:0]` into `VGAReg`, which connects to the generator's `BgColor`.

### 3e. The Instruction Subset

| Class | Instructions |
|---|---|
| Register Arithmetic and Logic | add, sub, and, or, xor, sll, srl, sra, slt, sltu |
| Immediate Arithmetic and Logic | addi, andi, ori, xori, slli, srli, srai, slti, sltiu |
| Loads | lb, lbu, lh, lhu, lw |
| Stores | sb, sh, sw |
| Conditional Branches | beq, bne, blt, bge, bltu, bgeu |
| Direct Jump | jal |
| Register-Indirect Jump | jalr |
| Upper Immediate | lui, auipc |
| Memory Ordering | fence, implemented as a no-op |
| Environment | ecall, ebreak, implemented as terminal bare-metal traps |

---

## 4. Verification

### 4a. Methodology

The tests are RISC-V assembly programs, not vectors. It's also important to note that I had AI write the actual assembler (asm.py) that turns the tests into hex. 

The testbench self-checks against the expected architectural state, so a failure is a named assertion, not a waveform.

### 4b. Regression Table

| Test | Checks | What It Exercises |
|---|---|---|
| T1 I-type | 11/11 | Immediate arithmetic and logic |
| T2 R-type | 10/10 | Register arithmetic and signed comparisons |
| T3 Load/Store | 9/9 | Address calculation and store forwarding |
| T4 Load-Use | 8/8 | Load-use stalls and dependent instructions |
| T5 Branch | 7/7 | Branch resolution and wrong-path flushing |
| T6 Direct Jump | 7/7 | Link value and wrong-path flushing |
| T7 Forwarding | 6/6 | Dependent arithmetic and forwarding |
| T8 Loop/Overflow | 7/7 | Branch prediction and signed overflow |
| T9 Shift/XOR | 15/15 | Shift and XOR operations |
| T10 Unsigned Comparison | 11/11 | Unsigned less-than operations |
| T11 Branch Conditions | 12/12 | Signed and unsigned branch conditions |
| T12 Upper Immediate | 8/8 | Upper-immediate loading |
| T13 PC-Relative Immediate | 7/7 | Adding an upper immediate to the PC |
| T14 Indirect Jump | 14/14 | Register-indirect destinations and links |
| T15 Byte Loads | 14/14 | Byte selection and extension |
| T16 Halfword Loads | 8/8 | Halfword selection and extension |
| T17 Partial Stores | 4/4 | Byte and halfword stores |
| T18 Environment Call | 4/4 | Terminal trap and halted Fetch |
| T19 Breakpoint | 3/3 | Terminal trap and halted Fetch |
| T20 Fence | 2/2 | No-op fence behavior |
| T21 Call/Return | 5/5 | Repeated and nested calls with different return destinations |
| T22 Incorrect Return Prediction | 4/4 | Recovery from an incorrect stack prediction |
| Total | 176/176 | 22 programs |
    
### 4c. What Is NOT Verified

1. No formal verification
2. Excluded official tests for fence_i and ma_data.
3. No lockstep against a golden model such as Spike
4. No UART testbench in the repo
5. VGA has never been displayed on a monitor
6. No on-board capture

### 4d. Hardware Test Results

A test of every printable ASCII code, 0x20 through 0x7e, was performed eight times. The host side is stdlib `termios` at 115200 8N1, one byte at a time, reading back between sends. The board's micro USB is a dual-channel FT2232H. Channel A is the JTAG programmer, channel B is a USB serial bridge wired to `UART_TXD_IN` (C4) and `UART_RXD_OUT` (D4). No external hardware is needed for the demo.

| Test | Sent | Returned | Errors |
|---|---|---|---|
| Before Receiver Fix | 23 | 23 | 2, both bit 0 |
| After Receiver Fix | 23 | 23 | 0 |
| Stress, Printable ASCII x8 | 760 | 760 | 0 |

### 4e. Defects Found On Hardware

When I attempted to implement the processor onto the board, a few errors came up that are documented here.

#### Defect 1: `DCache` Driven From Two `always_ff` Blocks

Note: this writeup is for an older implementation of the cache.

The implementation stopped before `opt_design` with **2048 DRC errors**, which is 64 words * 32 bits, encompassing the entire cache. 

```
ERROR: [DRC MDRV-1] Multiple Driver Nets: Net processor/DCache[0][0][3]_128[0]
  has multiple drivers: DCache_reg[0][0][3][0]/Q, and DCache_reg[0][0][3][0]__0/Q
```

The error came from `DCache` being written in two separate `always_ff` blocks. One was the refill of the DCache and the other was the write hit. This wasn't caught initially because both conditions were correct and mutually exclusive. 

iverilog doesn't actually enforce SystemVerilog's single-driver rule on a `logic` variable. It schedules both nonblocking assignments. Since the conditions never fire on the same cycle, no conflict ever appears. However, on a physical board, the variable became two register banks, so Vivado built `DCache_reg[...]` and `DCache_reg[...]`, tied both outputs to one net, and the DRC checker refused it.

**Fix:** the fix was rather obvious. I moved the write-hit assignment into the same `always_ff` block that the refill sits in. Both conditions were already mutually exclusive so behavior turned out unchanged. 

The lesson to take away from this is that simulation passing does not mean synthesis will pass, and testing is always required.

#### Defect 2: UART Receiver Sampled Bit 0 On The Bit Edge

The first echo test on hardware returned every byte, with two of 23 corrupted:

```
sent    : Hello from the Nexys A7
received: Hello from the Nexys A7

'e' 0x65 -> 'd' 0x64
'A' 0x41 -> '@' 0x40
```

Both errors are bit 0 cleared. Frame count was exact, so the receiver detected all 23 start bits and the transmitter returned 23 well-formed frames. 

##### Root Cause

The issue was caused by two bugs, both oversights on my end:

1. **`Count` was declared `logic [9:0]`**, holding 0 to 1023, but compared `1301` in two places. Given `Count` cannot count past 1023, the comparisons never happened which made the 1.5 bit-time sample for the first bit not possible.
2. **The index block advanced `Index` on `Count == 867` unconditionally**, without excluding the first index. So the first bit period ended one full bit time after `Busy`, not 1.5. 

The receiver was sampling the transition itself. When the sample won the race it read the correct bit, and when it lost it read the start bit's 0.

##### Why Bits 1 Through 7 Survived

By accident, when `Index` advanced at 867, the counter did not reset that cycle, so it climbed to 1023, wrapped, and counted to 867 again. That made bit 1's period 1024 cycles instead of 868, which pushed every later sample about 156 cycles past its bit edge. The frame decoded because of this rollover.

| Bit | Sample Point, Cycles From `Busy` | Ideal Center | Position In Bit |
|---|---|---|---|
| 0 | 868 | 1302 | Exactly On The Leading Edge |
| 1 | 1892 | 2170 | 18% In |
| 2+ | +868 Each | +868 Each | 18% In |

##### Fix

I made two adjustments. Firstly, I widened `Count` to `logic [10:0] Count`, and then I made `Index` advance on `Count == 1301` when `Index == 0`, else on `Count == 867`. 

After these corrections, samples now land at 1301, 2169, and 3037 cycles from `Busy`. This is consistent against the ideal centers.

#### Why Simulation Never Caught It

Another oversight by me. While the processor, cache, branch predictor, and vga all had testbenches, the uart lacked one.

---

## 5. Results 

### 5a. Branch Prediction

The branch prediction consists of a 64-entry table of 2-bit saturating counters, a 64-entry branch target buffer storing where the most recent jumps/branches went, and an 8-entry return address stack storing where jalr instructions should return to.

| Machine | T8 Mispredicts | T8 Cycles | T21 Cycles | T22 Cycles |
|---|---|---|---|---|
| Not Taken, No BTB | 31 | 263 | 97 | 55 |
| Always Taken, No BTB | 30 | 291 | 97 | 55 |
| Two-Bit Counters, No BTB | 2 | 206 | 97 | 55 |
| Backward Taken, No BTB | 1 | 203 | 97 | 55 |
| Current, Return Prediction Off | 1 | 174 | 97 | 55 |
| Current | 1 | 174 | 91 | 55 |

| Reset State | T8 Mispredicts | T8 Cycles | T21 Cycles | T22 Cycles |
|---|---|---|---|---|
| StronglyTaken | 1 | 174 | 91 | 55 |
| WeaklyTaken, Current | 1 | 174 | 91 | 55 |
| WeaklyNotTaken | 1 | 174 | 91 | 55 |
| StronglyNotTaken | 2 | 177 | 91 | 55 |

For no BTB, an important finding is that not-taken happens to be faster than always-taken. This is because not-taken fetches each address sequentially, where the next sequential address has been calculated before the instruction. Always-taken must wait for the instruction to arrive so its destination can be calculated.

### 5b. D-cache

The D-cache is built from 8 sets, 4 ways, 16 words per line, 512 words total, write-back, write-allocate, with a direct memory write on store misses.

Forced misses are produced by invalidating cache entries while retaining the refill logic. AMAT means average memory access time. This bench calculates it as 1 + data-stall cycles / accesses. Consequently, the D-cache baseline reports 21 cycles per access despite the timer being loaded with 15.

| Benchmark | Accesses | Hits | Misses | Hit Rate | AMAT | Forced-Miss Cycles | Cached Cycles | Speedup |
|---|---|---|---|---|---|---|---|---|
| B1 Stream | 256 | 240 | 16 | 93.8% | 2.25 | 6957 | 2157 | 3.23x |
| B2 Reuse Fits | 512 | 504 | 8 | 98.4% | 1.31 | 13915 | 3835 | 3.63x |
| B3 Reuse Thrash | 4096 | 3840 | 256 | 93.8% | 2.25 | 110681 | 33881 | 3.27x | 
| B4 Conflict | 96 | 93 | 3 | 96.9% | 1.62 | 2158 | 298 | 7.24x |
| B5 Store Stream | 256 | 240 | 16 | 93.8% | 2.25 | 6684 | 1884 | 3.55x |

All tests can be reproduced by `make cache`.

B1 and B3 land on identical hit rates, despite B3 having four times the reuse. That gap against B2 is the capacity miss, made visible. 

It's also important to note that the 15-cycle latency is my own construction. This is not a speedup against a real machine, and slow memory provides a way to show measurable statistics from the cache.

### 5c. I-Cache

The I-cache is built from 8 sets, 1 way, 8 words per line, 64 words total. It is read-only and fills a line on a read miss. It is simple because instruction memory is loaded before execution and only read while the program runs. It does not need store handling, dirty bits, or write-back logic:

| Benchmark | Fetches | Hits | Misses | Hit Rate | Forced-Miss Cycles | Cached Cycles | Speedup |
|---|---|---|---|---|---|---|---|
| T1 Straight-Line | 15 | 13 | 2 | 86.7% | 271 | 50 | 5.42x | 
| T8 Loop | 139 | 137 | 2 | 98.6% | 2503 | 174 | 14.39x | 
| T14 Indirect Jump | 41 | 36 | 5 | 87.8% | 744 | 149 | 4.99x |
| T21 Call/Returns | 39 | 36 | 3 | 92.3% | 703 | 91 | 7.73x |

All tests can be reproduced by `make icache`.

### 5d. Cache Organization

This section is purely to detail the differences in the I-cache and D-cache for future reference.

| Property | I-Cache | D-Cache |
|---|---|---|
| Sets | 8 | 8 |
| Ways | 1 | 4 |
| Words Per Line | 8 | 16 |
| Bytes Per Line | 32 | 64 |
| Total Capacity | 256 bytes | 2 KiB |
| Replacement | Direct-mapped | Tree-based pseudo-LRU |
| Set Index | `PCF[7:5]` | `ALUResultM[8:6]` |
| Tag | `PCF[15:8]` | `ALUResultM[15:9]` |
| Word Selection | `PCF[4:2]` | `ALUResultM[5:2]` |
| Writes | Read-only | Store hits dirty the line; dirty victims write back |
| Miss Handling | Fill eight-word line | Fill sixteen-word line in four four-word transfers |
| Store Miss | N/A | Direct memory write plus line allocation |

### 5e. Associativity

B1/B5 stream through data without revisiting it. B2 fits even in the smallest configuration. B3 exceeds every configuration. B4 repeatedly accesses three lines mapped to one set.

| Benchmark | Direct-Mapped Cycles | 2-Way Cycles | 4-way Cycles | Moved? |
|---|---|---|---|---|
| B1 Stream | 2157 | 2157 | 2157 | No |
| B2 Reuse Fits | 3835 | 3835 | 3835 | No |
| B3 Reuse Thrash | 33881 | 33881 | 33881 | No |
| B4 Conflict | 2158 | 2158 | 298 | Yes |
| B5 Store Stream | 1884 | 1884 | 1884 | No |

The direct-mapped configuration is 8 sets and 16 words per line, 128 words/512 bytes total. The 2-way configuration is 8 sets, 2-way, and 16 words per line, 256 words/1 KiB total. The 4-way configuration is 8 sets, 4 ways, and 16 words per line, 512 words/2 KiB total.

Here is the B4 set:

| Configuration | Hits | Misses | Hit Rate | Speedup vs Direct-Mapped |
|---|---|---|---|---|
| Direct-Mapped | 0 | 96 | 0% | 1.00x |
| Two-Way | 0 | 96 | 0% | 1.00x |
| Four-Way | 93 | 3 | 96.9% | 7.24x |

### 5f. Static Timing

#### Results Across Builds

Same RTL in every row. The only variable is the program in `memory.hex` and the implementation strategy.

| Build | ROM Contents | Constraint | WNS | Failing Endpoints |
|---|---|---|---|---|
| VGA, Default Strategy | `vgatest` | 10.00ns | **+0.217ns** | 0 / 11080 |
| Echo, Default Strategy | `echo` | 10.00ns | -0.045ns | 28 / 11142 |
| Echo, Performance_ExplorePostRoutePhysOpt | `echo` | 10.00ns | -0.154ns | 24 / 11142 |
| Echo, Default Strategy | `echo` | 10.50ns | +0.137ns | 0 / 11144 |
| Echo, Repo `build.tcl` As Committed | `echo` | 10.00ns | -0.242ns | 52 / 11142 |

The core is marginal at 100MHz on this part. Whether it closes depends on what is in the instruction ROM.

Attempts at physical optimization made the timing worse. 

The table shows -0.242ns and 52 failing endpoints while section 4d showed 760 bytes returning with zero errors. This is because WNS is quoted at the slow process corner and a part on a desk has margin over that corner.

#### The Critical Path

Stable across every build:

```
Source:          processor/A2E_reg[*]/C       (or A1E_reg[*])
Destination:     processor/InstrD_reg[*]/CE   (or PCPlus4D_reg[*]/CE)
Data Path Delay: 9.404ns (logic 3.126ns 33%, route 6.278ns 67%)   @ 10.00ns
Logic Levels:    15 (CARRY4=7 LUT3=1 LUT4=3 LUT5=1 LUT6=3)  
```

It starts at an operand register in Execute, passes through the forwarding mux into `RD2EI`, through the `ALUSrcBE` mux, down all seven CARRY4 blocks of the 32-bit ALU adder, and terminates at the clock enable of a Decode-stage pipeline register, which is a stall signal.

In plain terms: the design computes a full 32-bit addition and then uses that result to decide whether to freeze the pipeline, all in one cycle. `MemStall` depends on a cache hit detection, which depends on the address, which is the ALU result.

This is a design decision, though it inhibits my processor at running greater than ~100MHz. Between 67% and 73% of the path is routing rather than logic.

---

## 6. Architecture

### 6a. Block Diagram

**Datapath**

```
+-------------+     +-------------+     +-------------+     +-------------+     +-------------+
| F: Fetch    |     | D: Decode   |     | E: Execute  |     | M: Memory   |     | W: Writeback|
| PCF, I-cache| F/D | RegFile     | D/E | ALU         | E/M | ALUResultM  | M/W | Result mux  |
| InstrF     |---->| Decode      |---->| BranchTaken |---->| D-cache or  |---->| WD3W        |
| PCHold     |     | Extend      |     | PCTargetE   |     | peripheral  |     | -> RegFile  |
+-------------+     +-------------+     +-------------+     +-------------+     +-------------+
       ^                                      ^  ^                 |                  |
       |                                      |  +-----------------+                  |
       |                                      |       ALUResultM forwarding           |
       |                                      +---------------------------------------+
       |                                                      WD3W forwarding
       +--- Execute correction: PCTargetE or PCPlus4E

                +------------------------------------------------------+
                | Hazard Unit                                          |
                | Register dependencies -> ForwardAE, ForwardBE        |
                | lwStall, cache waits, traps -> StallF..W as required  |
                | Recovery, load-use, traps, startup -> FlushD, FlushE  |
                +------------------------------------------------------+
```

**Fetch and prediction**

```
                        PCF
                         |
           +-------------+-------------------------+
           |                                       |
           v                                       v
+-------------------------+           +-------------------------+
| Prediction lookup       |           | I-cache                 |
| BTB: 64 tagged targets   |           | 8 sets x 1 way x 8 words |
| BranchState: 64 x 2 bits |           | 64 words, 256 bytes      |
| RAS: 8 return addresses  |           | Read-only, fill on miss  |
+-------------------------+           +-------------------------+
           |                                       |
           |                              registered output
           |                                       |
           |                                       v
           |                          InstrF + PCHold + prediction Hold
           |                                       |
           |                        +--------------+--------------+
           |                        |                             |
           |                        v                             v
           |                 F/D register                  Backward fallback
           |                 -> Decode                     on BTB miss
           |                                               PCTargetF
           v                                                    |
+-----------------------------------------------------------------------+
| PCFNext mux, highest priority first                                    |
| 01: Execute correction -> PCTargetE or PCPlus4E                         |
| 10: BTB prediction -> TargetBuffer, or RAS top for a return             |
| 11: Backward fallback -> PCTargetF                                     |
| 00: Sequential -> PCPlus4F                                             |
+-----------------------------------------------------------------------+
           |
           +----> PCF on the clock when Fetch is not stalled

Execute -> update BranchState and BTB; push PCPlus4E for calls writing x1
Fetch   -> pop RAS when using a return prediction (Execute push wins)
Recovery/fallback -> ClearInstr clears the extra wrong-path fetched word

I-cache miss -> IIdle/IFetch control -> IMemStall -> holds F..W
               |
               +---- InstrMem: 16,384 words, 64 KiB
                     modeled 15-cycle memory delay
```

**Memory hierarchy, hanging off the M stage**

```
                         ALUResultM (address)
                                  |
                         ALUResultM[16]
                           0 /          \ 1
                            /            \
          +-------------------------+   +--------------------------------+
          | D-cache                 |   | Memory-mapped peripherals      |
          | 8 sets x 4 ways          |   | 0x10000 Store      UART TX      |
          | 16 words per line       |   | 0x10004 Load       UART status  |
          | 512 words, 2 KiB         |   | 0x10008 Load       UART RX      |
          | Write-back              |   | 0x1000C Load/Store VGA color    |
          | Write-allocate          |   +--------------------------------+
          | Tree-based pseudo-LRU   |
          +-------------------------+
                    |           ^
        dirty victim|           |line fill
                    v           |
          +-------------------------+
          | DIdle / DFetch control  |----> DMemStall -> holds F..W
          | Beat: four transfers    |
          | Four words per transfer |
          +-------------------------+
                    |           ^
                    v           |
          +-----------------------------------------------------+
          | Main data memory: 64 KiB total                       |
          | DataMem0    DataMem1    DataMem2    DataMem3          |
          | 16 KiB      16 KiB      16 KiB      16 KiB            |
          | Bank: address[3:2]    Row: address[15:4]              |
          | Modeled 15-cycle delay before line transfers         |
          +-----------------------------------------------------+

Store hit:  WDM -> D-cache; mark the line dirty
Store miss: WDM -> selected DataMem bank, and allocate a cache line
Load hit:   D-cache -> RDM -> byte/halfword selection -> Writeback
```

### 6b. Memory Map

MMIO is selected by address bit 16, register by bits 3:2. 

| Address | Access | Register |
|---|---|---|
| 0x10000 | Store | UART transmit, low byte of stored word |
| 0x10004 | Load | Status: bit 0 TxBusy, bit 1 RxReady |
| 0x10008 | Load | UART receive; the load itself clears RxReady |
| 0x1000C | Load/Store | VGA background color, low 12 bits |

A load at 0x10008 or a load at 0x1000C from the VGA register has a side effect of clearing the ready flag. The decode is also a single address bit, which is cheap and is why it costs address space.

### 6c. Utilization Table

Post-implementation, echo build, xc7a100tcsg324-1:

| Resource | Used | Available | % |
|---|---|---|---|
| Slice LUTs | 4480 | 63400 | 7.07 |
| Slice Registers | 2653 | 126800 | 2.09 |
| LUT as Memory | 748 | 19000 | 3.94 |
| Block RAM Tile | 0 | 135 | 0.00 |
| Bonded IOB | 18 | 210 | 8.57 |

The VGA build lands within 2% of these numbers. Zero block RAM: `InstrMem`, `RegFile`, `DataMem`, and `DCache` all inferred as distributed RAM in LUTs, which is what the 748-LUT-as-memory figure is.

---

## 7. Repo Layout

`pipelinedproject/` is the core repo and holds the core processor, uart echo, vga, compiled C, rv32ui tests, Makefile, BRANCH_PREDICTOR, and README. It also contains memory.hex, which is where the processor reads from, and the hex assembler at asm.py.

`pipelinedproject/processor` holds the actual processor and its related testbenches.

`pipelinedproject/uart` contains the transmitter and receiver modules for the UART Echo. 

`pipelinedproject/vga` contains the pattern generator in vgagenerator.sv along with its related testbenches.

`pipelinedproject/fpga` contains related code for Vivado and the actual top file used to link the processor, uart echo transmitter/receiver, and vgagenerator modules together.

`pipelinedproject/C_test` contains the basic C programs compiled on the core and the dependencies to make it work.

`pipelinedproject/isa_tests` contains the rv32ui tests and its dependencies.

---

## 8. Limitations

This section is meant to illustrate deliberate design choices I made regarding specific conditions of my processor along with shortcomings of my design.

1. The 15-cycle memory is synthetic, so cache speedups are against a slowness I created.
2. The loop-exit mispredict is unfixable by my design because a per-address two-bit predictor cannot predict it.

---

## 9. Authorship and References

Every design module in this repository is mine. The testbenches, scripts, constraints, and the tools used to build and measure the design were written or driven with AI assistance. The split below is exact:

| Component | Authorship |
|---|---|
| Pipeline Datapath and Control | Mine |
| Hazard Unit | Mine |
| Two-Bit Predictor and BTB | Mine | 
| Return Address Stack | Mine |
| D-Cache and I-Cache | Mine |
| UART and VGA Design Modules | Mine |
| Peripheral Address Decoding | Mine |
| `fpga/top.sv` | Mine |
| Core, Cache, Write-Back, ISA, Compiled-C, and VGA Testbenches | AI Tooling |
| Assembler and Benchmark Programs | AI Tooling |
| `measure_branch.py`, Makefile, and Compiled-C Support Scripts | AI Tooling |
| Vivado Scripts and XDC Constraints | AI Tooling |
| Hardware Measurements and Timing Analysis | AI-Assisted |
| This README | AI-Assisted |

The most important reference to this project was Harris & Harris's Digital Design and Computer Architecture: RISC-V Edition, which taught me the ins and outs of how these systems work. I would like to extend a thank you to them personally:
- Harris and Harris, *Digital Design and Computer Architecture: RISC-V Edition*.
