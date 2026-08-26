# riscv-pipelined-core

---

## 1. Overview

riscv-pipelined-core is a 5-stage pipelined RV32I subset core that implements thirteen instructions, a UART Echo, a VGA Pattern Generator, 2-bit branch prediction, and a D-cache memory hierarchy. It is written in SystemVerilog and runs on a Nexys A7 FPGA. 

| Claim | Number |
|---|---|
| Result | 65/65 checks, 8 programs |
| Branch Prediction | 195 (always-taken) --> 139 cycles, 29% |
| D-cache | 2.12x to 6.17x speedup |
| Associativity | conflict benchmark 0% --> 96.9% hit rate |

---

## 2. Quick Start

```
make            # 65-check regression
make cache      # D-cache benchmark suite
make vga        # VGA timing benchmark
make top        # core drives VGA, integration
```

iverilog is required along with Python 3 for asm.py.

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
4. FPGA timing closure unconfirmed, WNS unchecked since the predictor landed on the fetch path
5. No I-cache, so instruction fetch is unmodeled

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

Both cycles w/o and cycles w/ column are reproduce from ``make cache``.

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
          +---------------------+     +----------------------------+
          | D-cache             |     | MMIO                       |
          | 8 sets x 2 ways     |     | 0x400  st  UART TX byte    |
          | 4 words / line      |     | 0x404  ld  TxBusy, RxReady |
          | 64 words total      |     | 0x408  ld  UART RX, clears |
          | write-through       |     | 0x40C  st  VGA bg colour   |
          | no write-allocate   |     +----------------------------+
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

| Mine | Tooling, built with AI assistance |
|---|---|
| pipelined.sv (core, predictor, cache, MMIO) | processor/tb.sv |
| transmitter.sv, receiver.sv | processor/tb_cache.sv |
| vgagenerator.sv | asm.py, Makefile, build.tcl |
| top.sv | All tests and benchmarks including tb_vga.sv and tb_top.sv |
| | Block diagram in 6a was made with AI assistance |

The most important reference to this project was Harris & Harris's Digital Design and Computer Architecture: RISC-V Edition, which taught me the ins and outs of how these systems work. I would like to extend a thank you to them personally:
- Harris and Harris, Digital Design and Computer Architecture: RISC-V Edition.
