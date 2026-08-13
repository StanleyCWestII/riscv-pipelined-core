# Branch prediction — where this stands

**Last touched:** 2026-08-12
**State:** complete. 64-entry 2-bit saturating predictor, regression 65/65.

---

## What the machine does now

| stage | what happens |
|---|---|
| F | `isBranchF` decodes `InstrF[6:0]`. `PCTargetF = PCF + Bimm`. `PredictedF` reads the counter at `BranchState[PCF[7:2]]`. If it's a branch and the counter says taken, fetch redirects to the target. |
| D | `isBranchD` and `PredictedD` carry both facts down. |
| E | `MisPredict = ZeroE ^ PredictedE`. On a mispredict, redirect and flush. The counter at `BranchState[PCE[7:2]]` is updated from `ZeroE`. |

`PCSrcE` is 2 bits and means **mispredicted**, not **taken**:

| code | PCFNext | meaning |
|---|---|---|
| `2'b00` | `PCPlus4F` | sequential |
| `2'b01` | `PCTargetE` or `PCPlus4E` | E-stage recovery, address depends on direction |
| `2'b10` | `PCTargetF` | F-stage predicted target |

Recovery splits by direction inside the `2'b01` arm:
`(isBranchE & ~ZeroE) ? PCPlus4E : PCTargetE`.

### The counter table

64 entries × 2 bits, indexed `PCF[7:2]` on the read in F and `PCE[7:2]` on the
write in E. Two different indices because `PCF` has moved on two instructions
by the time the branch resolves.

Instruction memory is 64 words, so every instruction has its own entry and
**there is no aliasing**. Real cores can't afford one entry per instruction and
index a smaller table with low PC bits, which lets unrelated branches collide.
Not a constraint at this size.

### Encoding

```
StronglyTaken    = 2'b00      MSB = 0  ->  predict taken
WeaklyTaken      = 2'b01
WeaklyNotTaken   = 2'b10      MSB = 1  ->  predict not taken
StronglyNotTaken = 2'b11
```

The prediction is one bit, `~BranchState[PCF[7:2]][1]`. No decode logic. The
inverter is there because this encoding counts *down* toward taken; flipping
the four localparams would remove it and change nothing else.

Reset is `WeaklyTaken`, chosen by measurement (see below).

### No BTB

The instruction memory read is combinational (`assign InstrF = InstrMem[PCF[7:2]]`),
so instruction bits are valid in the same cycle as the address and the target
adder can live in F. Real cores need a Branch Target Buffer because synchronous
SRAM doesn't return the instruction until the next cycle.

---

## Measured results

`tb.sv` counts branches and mispredicts per branch PC, and cycles until the
program reaches its parking spin loop. Parking loops are excluded from all
counts; without that the spin loop executes a branch every cycle and drowns
the real data.

T8 (`t8_loop.s`), 132 dynamic instructions, no loads so no stall cycles:

| machine | mispredicts | cycles | CPI |
|---|---|---|---|
| predict-not-taken (original) | 31 | 197 | 1.49 |
| always-taken (phase 1) | 30 | 195 | 1.48 |
| 2-bit counters, reset StronglyTaken | 3 | 141 | 1.07 |
| **2-bit counters, reset WeaklyTaken** | **2** | **139** | **1.05** |
| no-mispredict floor | 0 | 135 | 1.02 |

**29% fewer cycles than the always-taken machine.** Whole regression: 31
mispredicts down to 3.

Per branch in T8:

| pc | behaviour | always-taken | 2-bit |
|---|---|---|---|
| `0x14` `beq x2,x0,exit` | not taken 30x, taken 1x | 30 | 2 |
| `0x18` `beq x0,x0,loop` | taken 30x | 0 | 0 |

The always-taken machine was not an improvement over the original. It moved the
entire cost from the backward branch to the exit branch, 30 for 30. The counter
table is what actually removed it, because the two branches get separate
entries and each sees a consistent pattern.

### Reset state, decided by measurement

All four reset states, whole-regression mispredicts:

| reset | total | T8 `0x14` | T8 `0x18` | one-shot branches |
|---|---|---|---|---|
| StronglyTaken | 4 | 3 | 0 | 1 |
| **WeaklyTaken** | **3** | 2 | 0 | 1 |
| WeaklyNotTaken | 5 | 1 | 1 | 3 |
| StronglyNotTaken | 6 | 1 | 2 | 3 |

The general lesson: **weak reset states adapt twice as fast as strong ones.**
From a weak state one wrong guess flips the prediction; from a strong state it
takes two. That's structural and worth keeping.

The taken-vs-not-taken half of the result is **not** general. Four of the five
branch sites in the suite execute exactly once, so there is no learning and the
reset state simply *is* the prediction. Those happen to be mostly taken here.
On real code, branches execute enough times that warmup amortizes to nothing
and the reset state would be unmeasurable.

---

## What's deliberately not done

The remaining 7 cycles above 132 on T8 break down as:

- **3 cycles pipeline fill.** Structural, and a fixed cost. On a 300-iteration
  version of the same loop it's 0.25% of CPI instead of 2.3%.
- **2 cycles, the loop exit.** A branch that goes one way 30 times and then
  flips cannot be predicted by any saturating counter. Catching it needs a loop
  predictor or ~31 bits of global history. Out of proportion to a 2-cycle win.
- **2 cycles, cold start on `0x14`.** This one is fixable with a static hint:
  backward branches are usually loops and usually taken, forward branches
  usually aren't. The signal is free, `InstrF[31]` is the sign of the B-type
  immediate already computed for `PCTargetF`. Cost is a valid bit per entry,
  64 more flip-flops, to know whether to trust the counter or the hint.
  For T8 it is right on both branches and would take 139 to 137.

64 flip-flops for 2 cycles is a bad trade here, and the machine is already
within 3% of a floor it cannot cross. Not building it.

---

## Scope of the CPI claim

1.05 is T8 only, and T8 is the friendliest possible workload for a branch
predictor: a tight loop with two branch sites, one perfectly predictable.

More importantly, **there is no memory system in this number.** DataMem is a
64-word array that answers in one cycle, always. Real CPI is dominated by cache
misses, not branches. T8 also has no loads, so no load-use stalls landed in it.

The defensible claim is the delta, not the absolute:

> 64-entry 2-bit saturating branch predictor. Mispredicts on the loop benchmark
> dropped from 30 to 2, cycles from 195 to 139, a 29% reduction. Full 65-check
> regression still passing.

---

## Still open

**Vivado timing.** The F-stage immediate extractor, the 32-bit target adder,
and now the counter table read all sit on the fetch critical path, which
previously had almost nothing on it. Check WNS after synthesis. Should be fine
at 100 MHz, but confirm rather than assume.

---

## Reference

The 2-bit saturating counter is Smith's predictor:
James E. Smith, "A Study of Branch Prediction Strategies," ISCA 1981.

Harris & Harris cover branch prediction in the advanced microarchitecture
section of Chapter 7 (RISC-V edition).
