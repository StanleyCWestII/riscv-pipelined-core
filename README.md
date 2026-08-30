# riscv-pipelined-core

---

## 1. Overview

riscv-pipelined-core is a 5-stage pipelined RV32I subset core that implements thirteen instructions, a UART Echo, a VGA Pattern Generator, 2-bit branch prediction, and a D-cache memory hierarchy. It is written in SystemVerilog and runs on a Nexys A7 FPGA. 

| Claim | Number |
|---|---|
| Regression | 65/65 checks, 8 programs |
| Branch Prediction | 195 (always-taken) --> 139 cycles, 29% |
| D-cache | 2.12x to 6.17x speedup |
| Associativity | conflict benchmark 0% --> 96.9% hit rate |
| UART Echo | 760/760 bytes returned, zero errors |

---

## 2. Quick Start

### 2a. Simulation

```
make            # 65-check regression
make cache      # D-cache benchmark suite
make vga        # VGA timing benchmark
make top        # core drives VGA, integration
```

iverilog is required along with Python 3 for asm.py.

### 2b. Hardware

Tested on a Nexys A7-100T, part xc7a100tcsg324-1. Assemble a program first, since the bitstream contains whatever is in memory.hex at synthesis time:

```
python3 asm.py uart/echo.s memory.hex   # or vga/vgatest.s
```

The pre-synthesis hook below is required. pipelined.sv:313 loads the ROM with $readmemh("memory.hex", InstrMem), and Vivado resolves that relative path against the synthesis run directory, not the repo root. Adding the file with add_files does not fix it. Run from Tcl console:

```
set_property STEPS.SYNTH_DESIGN.TCL.PRE "fpga/pre_synth.tcl" [get_runs synth_1]
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
open_run impl_1
report_utilization
report_timing_summary -delay_type max -max_paths 3
```

where pre_synth.tcl is two lines:

```
set root [file dirname [file dirname [file normalize [info script]]]]
file copy -force [file join $root memory.hex] [file join [pwd] memory.hex]
```

Check utilization before programming. Without the hook the ROM reads as empty, constant propagation removes the core outward from the fetch stage, and the result is a bitstream that programs normally and asserts DONE with roughly 30 LUTs in it. A small utilization number means the design was deleted.

To program, open the hardware manager with open_hw_manager, connect_hw_server, and open_hw_target, then program the device. If the target is found but reports no devices detected, then the board's power switch is off. The FT2232H is powered from USB and tells whether or not the board is on.

The echo demo needs no external hardware. Channel B of the FT2232H is a USB serial bridge wired to UART_TXD_IN and UART_RXD_OUT. Any 115200 8N1 terminal will do.

---

## 3. What This Project Is

### 3a. The Pipeline and Hazard Unit

The processor is split into five stages: Fetch, Decode, Execute, Memory, and Writeback. 

The Fetch stage includes the Program Counter, Instruction Memory, PCNext multiplexer and adder, and additional branch predictor logic with an extra adder to compute the predicted branch and wiring to actually predict a branch. 

The Decode stage includes the Register File and Extender. It defines the source registers and destination register while also sign-extending the immediate and passing these signals along to the Execute stage.

The Execute stage holds the 32-bit ALU, which features several multiplexers on its inputs which further depend on various control signals from the Control Unit. It performs addition, subtraction, and, or, and slt operations, and also defends against overflowing through several steps:
1. Determines whether the operation could overflow through the operand signs.
2. Determines whether the answer came out wrong through the operand signs.
3. Determines whether the result ACTUALLY overflowed.
4. The sign bit is flipped if it overflowed.
5. Pads the sign bit to 32 bits.

All in all, the Execute stage's main function is to produce ALUResult. 

The Memory stage holds Data Memory, MMIO logic for the UART Echo and VGA Pattern Generator, and additional logic for the D-cache. 

The Writeback stage is the final stage and is mainly a multiplexer which serves to determine what signal to write back to the register file. 

The Hazard Unit makes use of forwarding, flushing, and stalling to bypass typical pipelining errors. It holds the capability to stall all five stages and flush the Decode and Execute stages. Forwarding is decided by equality checks on the source and destination registers using a control signal ForwardAE and ForwardBE. The stall signals are decided off of two signals, lwStall and MemStall. lwStall fires when the instruction in Execute is a load and the instruction in Decode reads the register that load is about to write. MemStall is attached to the D-cache FSM and fires either on a cache miss or when in the Fetch state of the FSM.

### 3b. The Instruction Subset

| Class | Instructions |
|---|---|
| R-type | add, sub, and, or, slt |
| I-type ALU | addi, andi, ori, slti |
| Memory | lw, sw |
| Branch | beq |
| Jump | jal |

Missing from the current instruction set: xor, sll, srl, sra, sltu, xori, slli, srli, srai, sltiu, lb, lh, lbu, lhu, sb, sh, bne, blt, bge, bltu, bgeu, jalr, lui, auipc, ecall, ebreak, fence.

### 3c. Peripherals

The UART Echo features an independent transmitter in transmitter.sv that sends out each bit of the word. The other half, the receiver, in receiver.sv, collects and sends out the actual byte plus whether it is Valid.

The VGA Pattern Generator exists in vgagenerator.sv. It walks each pixel and fills in the 4-bit Red, Green, and Blue value to form a comprehensive RGB total for the pixel.

---

## 4. Verification

### 4a. Methodology

The tests are RISC-V assembly programs, not vectors. It's also important to note that I had AI write the actual assembler (asm.py) that turns the tests into hex. 

The testbench self-checks against the expected architectural state, so a failure is a named assertion, not a waveform.

### 4b. Regression Table

| Test | Checks | What It Exercises |
|---|---|---|
| T1 I-type | 11/11 | I-type Decode and Immediate Extension |
| T2 R-type | 10/10 | ALU Ops and Signed SLT |
| T3 load/store | 9/9 | Address Path and Store Data Forwarding |
| **T4 load-use** | **8/8** | **Hazard: Stall** |
| T5 branch | 7/7 | Branch Resolution and Flush |
| T6 jal | 7/7 | Link Value and Squash |
| **T7 forwarding** | **6/6** | **Hazard: Forward** |
| T8 loop/overflow | 7/7 | Predictor and Signed Overflow |
| Total | 65/65 | N/A |
    
### 4c. What Is NOT Verified

1. No formal verification
2. No official riscv-tests compliance suite
3. No lockstep against a golden model such as Spike
4. No I-cache, so instruction fetch is unmodeled
5. No UART testbench in the repo
6. VGA has never been displayed on a monitor
7. No on-board capture

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

The implementation stopped before `opt_design` with **2048 DRC errors**, which is 64 words * 32 bits, encompassing the entire cache. 

```
ERROR: [DRC MDRV-1] Multiple Driver Nets: Net processor/DCache[0][0][3]_128[0]
  has multiple drivers: DCache_reg[0][0][3][0]/Q, and DCache_reg[0][0][3][0]__0/Q
```

The error came from `DCache` being written in two separate `always_ff` blocks. One was the refill of the DCache and the other was the write hit. This wasn't caught initially because both conditions were correct and mutually exclusive. 

iverilog doesn't actually enforce SystemVerilog's single-driver rule on a `logic` variable. It schedules both nonblocking assignments. Since the conditions never file on the same cycle, no conflict ever appears. However, on a physical board, the variable became two register banks, so Vivado built `DCache_reg[...]` and `DCache_reg[...]`, tied both outputs to one net, and the DRC checker refused it.

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

By accident, when `Index` advanced at 867, the counter did not reset that cycle, so it climbed to 1023, wrapped, and counted top 867 again. That made bit 1's period 1024 cycles instead of 868, which pushed every later sample about 156 cycles past its bit edge. The frame decoded because of this rollover.

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

### 5a. Branch Predictor

The branch predictor is a 64-entry table of 2-bit saturating counters, read in F on PCF[7:2], updated in E on PCE[7:2], no BTB. 

| Machine | Mispredicts | Cycles | CPI |
|---|---|---|---|
| predict-not-taken | 31 | 197 | 1.49 |
| always-taken | 30 | 195 | 1.48 |
| 2-bit, reset StronglyTaken | 3 | 141 | 1.07 |
| 2-bit, reset WeaklyTaken | 2 | 139 | 1.05 |
| no-mispredict floor | 0 | 135 | 1.02 |

Some important findings from this included always-taken producing basically zero improvement, as the cost shifted but did not improve. Also, the weak reset states adapt twice as fast as strong ones. 

See BRANCH_PREDICTOR.md for more extensive details.

### 5b. D-cache

The D-cache is built from 8 sets, 2 ways, 4 words per line, 64 words total, write-through, no write-allocate, LRU, behind a 15-cycle main memory.

| Benchmark | Hit-Rate | AMAT | Cycles w/o | Cycles w/ | Speedup |
|---|---|---|---|---|---|
| B1 Stream | 75.0% | 5.25 | 1546 | 730 | 2.12x |
| B2 Reuse Fits | 93.8% | 2.06 | 1572 | 552 | 2.85x |
| B3 Reuse Thrash | 75.0% | 5.25 | 12324 | 5796 | 2.13x |
| B4 Conflict | 96.9% | 1.53 | 1258 | 204 | 6.17x |

Both cycles w/o and cycles w/ column are reproduced from ``make cache``.

B1 and B3 land on identical hit rates, despite B3 having four times the reuse. That gap against B2 is the capacity miss, made visible. 

It's also important to note that the 15-cycle latency is my own construction. This is not a speedup against a real machine, and it was impossible to test this reliably without the latency due to my processor's small memory size.

### 5c. Associativity

| Benchmark | Direct-Mapped | 2-Way | Moved? |
|---|---|---|---|
| B1 Stream | 2.12x | 2.12x | No |
| B2 Reuse Fits | 2.85x | 2.85x | No |
| B3 Reuse Thrash | 2.13x | 2.13x | No |
| B4 Conflict | 1.00x, 0% Hit | 6.17x, 96.9% Hit | Yes |

In designing the 2-way cache, the capacity held constant, but organization changed. The design went from 16 lines of 4 words to 8 sets of 2 ways of 4 words. Both are 64 words total.

The first three benchmarks predicted no change, and it did not move. The benchmark was also purpose-built to isolate one variable: two addresses, 8 bytes of live data, colliding on one index.

Also, the direct-mapped build for B4 does not exist anymore. At 7a45382 the array was `logic [31:0] DCache [0:15][0:3]`, 16 blocks indexed on [7:4]. 

### 5d. Static Timing

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
              +---------------------------------+             +---------------------------------+
              | BranchState: 64 x 2-bit ctrs    |             | Hazard Unit                     |
              +---------------------------------+             | lwStall/MemStall -> StallF..W   |
                  | read PCF[7:2]              ^              | mispredict/lwStall -> FlushD,E  |
       +----------+                            | upd PCE[7:2] +---------------------------------+
       v                                       |                   v                   v
+-------------+  |  +-------------+  |  +-------------+  |  +-------------+  |  +-------------+
|      F      |  |  |      D      |  |  |      E      |  |  |      M      |  |  |      W      |
| PCF InstrMem|--|->| RegFile     |--|->| ALU   ZeroE |--|->| addr[10] ?  |--|->| Result mux  |
| PCTargetF   |  |  | Extend      |  |  | PCTargetE   |  |  | D$ or MMIO  |  |  | -> RegFile  |
+-------------+  |  +-------------+  |  +-------------+  |  +-------------+  |  +-------------+
       ^        F/D                 D/E   | ^     ^     E/M        |        M/W        |
       |                                  | |     |                |                   |
       |                                  | |     +----------------+                   |
       |                                  | |       forward from M                     |
       |                                  | +------------------------------------------+
       |                                  |   forward from W
       +----------------------------------+
          redirect on mispredict / jal  (PCSrcE)
```

**Memory hierarchy, hanging off the M stage**

```
                            ALUResultM  (address from E)
                                 |
                            addr bit 10
                          0 /          \ 1
                           /            \
          +---------------------+     +-------------------------------+
          | D-cache             |     | MMIO                          |
          | 8 sets x 2 ways     |     | 0x400  st     UART TX byte    |
          | 4 words / line      |     | 0x404  ld     TxBusy, RxReady |
          | 64 words total      |     | 0x408  ld     UART RX, clears |
          | write-through       |     | 0x40C  ld/st  VGA bg colour   |
          | no write-allocate   |     +-------------------------------+
          | LRU replacement     |
          +---------------------+
                     | Miss
                     v
          +---------------------+
          | refill FSM          |----> MemStall  (freezes F..W)
          | Idle <-> Fetch      |
          +---------------------+
                     |
                     v
          +---------------------+
          | DataMem, 15-cycle   |
          | synthetic latency   |
          +---------------------+
```

### 6b. Memory Map

MMIO is selected by address bit 10, register by bits 3:2. 

| Address | Access | Register |
|---|---|---|
| 0x400 | Store | UART transmit, low byte of stored word |
| 0x404 | Load | Status: bit 0 TxBusy, bit 1 RxReady |
| 0x408 | Load | UART receive; the load itself clears RxReady |
| 0x40C | Load & Store | VGA background color, low 12 bits |

The load at 0x408 has a side effect of clearing the ready flag. The decode is also a single address bit, which is cheap and is why it costs address space.

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

pipelinedproject/ is the core repo and holds the core processor, uart echo, and vga builds. It also contains memory.hex, which is where the processor reads from, and the hex assembler at asm.py.

pipelinedproject/processor holds the actual processor code in pipelined.sv, along with the testbench and other benchmarks associated with stressing the branch predictor and D-cache.

pipelinedproject/uart contains the transmitter and receiver modules for the UART Echo. 

pipelinedproject/vga contains the pattern generator in vgagenerator.sv along with its related testbenches.

pipelinedproject/fpga contains related code for Vivado and the actual top file used to link the processor, uart echo transmitter/receiver, and vgagenerator modules together.

pipelinedproject/ holds BRANCH_PREDICTOR.md, which is a more in-depth look into the processor's branch prediction.

---

## 8. Limitations

This section is meant to illustrate deliberate design choices I made regarding specific conditions of my processor along with shortcomings of my design.

1. The 15-cycle memory is synthetic, so cache speedups are against a slowness I created.
2. D-cache only, no I-cache, because fetch is combinational and the predictor depends on that.
3. Instruction memory is 64 words, so every branch gets its own predictor entry and aliasing cannot occur, which real cores cannot afford.
4. No BTB, because combinational fetch makes the target adder viable in F.
5. The loop-exit mispredict is unfixable by any saturating counter. It needs a loop predictor or ~31 bits of global history.
6. Only 13 instructions supported, not full RV32I.
7. The CPI figure contains no memory system.

---

## 9. Authorship and References

Every design module in this repository is mine. The testbenches, scripts, constraints, and the tools used to build and measure the design were written or driven with AI assistance. The split below is exact:

| Mine | AI-Assisted: Tooling, Instrumentation, Measurement |
|---|---|
| `pipelined.sv`: Pipeline Datapath and Control | `processor/tb.sv`, `processor/tb_cache.sv` |
| Hazard Unit: Forwarding, Stalls, Flushes | `vga/tb_vga.sv`, `vga/tb_top.sv` |
| 64-Entry 2-Bit Saturating Branch Predictor | `asm.py`, `Makefile`, `fpga/build.tcl` |
| 2-Way Set Associative D-Cache | `fpga/top.xdc`, `vga/vga.xdc` |
| MMIO Decode for UART and VGA | Block diagram in 6a |
| `transmitter.sv`, `receiver.sv` | Vivado Flow, Synthesis, and Timing Log Analysis |
| `vgagenerator.sv` | Host-Side Serial Test Harness Used In 4d |
| `fpga/top.sv` | Collection of the Tables in 5d and 6c |
| Both hardware defect fixes in 4e | `fpga/pre_synth.tcl` |

The most important reference to this project was Harris & Harris's Digital Design and Computer Architecture: RISC-V Edition, which taught me the ins and outs of how these systems work. I would like to extend a thank you to them personally:
- Harris and Harris, *Digital Design and Computer Architecture: RISC-V Edition*.
