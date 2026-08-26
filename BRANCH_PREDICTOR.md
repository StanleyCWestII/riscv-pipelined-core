# Branch Predictor

# 1. What The Processor Does Now

## 1a. The Changes In Each Stage

| Stage | What Happens |
|---|---|
| F | `isBranchF` decodes `InstrF[6:0]`. `PCTargetF = PCF + Bimm`. `PredictedF` reads the counter at `BranchState[PCF[7:2]]`. If it's a branch and the counter says taken, fetch redirects to the target. |
| D | `isBranchD` and `PredictedD` carry both facts down. |
| E | `MisPredict = ZeroE ^ PredictedE`. On a mispredict, redirect and flush. The counter at `BranchState[PCE[7:2]]` is updated from `ZeroE`. |

## 1b. PCSrcE

`PCSrcE` is 2 bits and means mispredicted, not taken.

| Code | PCFNext | Meaning |
|---|---|---|
| `2'b00` | `PCPlus4F` | Sequential |
| `2'b01` | `PCTargetE` or `PCPlus4E` | E-stage recovery, address depends on direction |
| `2'b10` | `PCTargetF` | F-stage predicted target |

Recovery splits by direction inside the `2'b01` arm:
`(isBranchE & ~ZeroE) ? PCPlus4E : PCTargetE`.

## 1c. The Counter Table

64 entries x 2 bits, indexed by `PCF[7:2]` on the read in F and by `PCE[7:2]` on the write in E. The two are separated because `PCF` has moved on two instructions by the time the branch resolves. 

The instruction memory is 64 words, so every instruction has its own entry and there is no aliasing. Real cores cannot afford one entry per instruction and index a smaller table with low PC bits, letting unrelated branches collide. This is not a constraint at this size. 

## 1d. Encoding

```
StronglyTaken    = 2'b00     MSB = 0 -> predict taken
WeaklyTaken      = 2'b01
WeaklyNotTaken   = 2'b10     MSB = 1 -> predict not taken
StronglyNotTaken = 2'b11
```

The prediction is one bit,  `~BranchState[PCF[7:2]][1]`. There's no decode logic, and the inverter exists because this encoding counts down towards taken.

Reset is `WeaklyTaken`, chosen by the below measurement.

## 1e. No BTB

The instruction memory read is combinational (`assign InstrF = InstrMem[PCF[7:2]]`), so instruction bits are valid in the same cycle as the address and the target adder can live in F. Real cores need a Branch Target Buffer because synchronous SRAM doesn't return the instruction until the next cycle. 

# 2. Measured Results

## 2a. Benchmarks

`tb.sv` counts branches and mispredicts per branch PC, and cycles until the program reaches its parking spin loop. Parking loops are excluded from all counts; without that the spin loop executes a branch every cycle and drowns the real data.

T8 (`t8_loop.s`), 132 dynamic instructions, no loads so no stall cycles:

| Machine | Mispredicts | Cycles | CPI |
|---|---|---|---|
| Predict-Not-Taken (Original) | 31 | 197 | 1.49 |
| Always-Taken (Phase 1) | 30 | 195 | 1.48 |
| 2-bit Counters, Reset StronglyTaken | 3 | 141 | 1.07 |
| 2-bit Counters, Reset WeaklyTaken | 2 | 139 | 1.05 |
| No-Mispredict Floor | 0 | 135 | 1.02 |

29% fewer cycles than the always-taken machine. Whole regression: 31 mispredicts down to 3.

Per branch in T8:

| PC | Behavior | Always-Taken | 2-Bit |
|---|---|---|---|
| `0x14` `beq x2, x0, exit` | Not Taken 30x, Taken 1x | 30 | 2 |
| `0x18` `beq x0, x0, loop` | Taken 30x | 0 | 0 |

The always-taken machine was not an improvement over the original. It moved the entire cost from the backward branch to the exit branch, 30 for 30. The counter table removed two branches because they get separate entries and each see a consistent pattern.

## 2b. Reset State

Mispredicts of each reset state:

| Reset | Total | T8 `0x14` | T8 `0x18` | One-Shot Branches |
|---|---|---|---|---|
| StronglyTaken | 4 | 3 | 0 | 1 |
| WeaklyTaken | 3 | 2 | 0 | 1 |
| WeaklyNotTaken | 5 | 1 | 1 | 3 |
| StronglyNotTaken | 6 | 1 | 2 | 3 |

The point is that weak reset states adapt twice as fast as strong ones. From a weak state one wrong guess flips the prediction, while a strong reset state takes two.

Taken vs not taken isn't as simple. Four of the five branch sites in the suite execute exactly once, so there is no learning and the reset state is the prediction here. For these tests, they are mostly taken but this changes with the instruction set.

# 3. CPI Claim

1.05 is T8 only, and T8 is the friendliest possible workload for a branch predictor with a tight loop with two branch sites, one perfectly predictable.



# 4. References

The 2-bit saturating counter is Smith's predictor:
James E. Smith, "A Study of Branch Prediction Strategies," ISCA 1981.

Harris & Harris cover branch prediction in the advanced microarchitecture section of Chapter 7 (RISC-V Edition).





















