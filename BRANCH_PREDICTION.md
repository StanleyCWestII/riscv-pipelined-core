# Branch prediction — where this stands

**Last touched:** 2026-08-12
**State:** phase 1 done, committed at `031263f`, regression 65/65.

---

## What works now

Fetch speculates. It no longer blindly takes `PCPlus4F`.

| stage | what happens |
|---|---|
| F | `isBranchF` decodes `InstrF[6:0]`. `PCTargetF = PCF + B-type immediate`. If it's a branch, fetch redirects to the target. |
| D | `isBranchD` carries the flag. |
| E | `MisPredict = ZeroE ^ isBranchE`. On a mispredict, redirect and flush. |

`PCSrcE` is now 2 bits and means **mispredicted**, not **taken**:

| code | PCFNext | meaning |
|---|---|---|
| `2'b00` | `PCPlus4F` | sequential |
| `2'b01` | `PCTargetE` or `PCPlus4E` | E-stage recovery, address depends on direction |
| `2'b10` | `PCTargetF` | F-stage predicted target |

The recovery address splits by direction inside the `2'b01` arm:
`(isBranchE & ~ZeroE) ? PCPlus4E : PCTargetE`. Predicted taken but
resolved not taken recovers to `PCPlus4E`; everything else, including
`jal`, recovers to `PCTargetE`.

**No BTB.** The instruction memory read is combinational
(`assign InstrF = InstrMem[PCF[7:2]]`), so the instruction bits are valid
in the same cycle as the address. Real cores need a Branch Target Buffer
because synchronous SRAM doesn't hand back the instruction until the next
cycle. Not a constraint here, so the target adder just lives in F.

**The predictor itself is static always-taken.** Every branch is predicted
taken. That's the piece that gets replaced next.

---

## What's left

### 1. The counter array
64 entries × 2 bits, indexed `PCF[7:2]`. Instruction memory is 64 words, so
every instruction gets its own counter and there is no aliasing. Needs a
reset that clears the whole array. ~5 lines.

### 2. Predict from the counter
The predict condition is bare `isBranchF` today. It becomes `isBranchF` AND
the MSB of that PC's counter. 1 line.

### 3. Carry the prediction bit down F → D → E  ← the one that bites

`isBranchE` currently does **two jobs at once**: "this is a branch" and
"we predicted taken." They are the same signal only because the static
predictor always says taken.

**The moment counters exist those become different facts**, and
`MisPredict = ZeroE ^ isBranchE` starts silently lying. A separate
`PredictedTakenD` / `PredictedTakenE` has to ride alongside `isBranchD` /
`isBranchE`. Declaration plus 4 register sites, ~5 lines.

### 4. Update the counter in E
On `BranchE`: saturating increment if `ZeroE`, decrement if not.

Index with **`PCE[7:2]`, not `PCF`** — by the time the branch reaches E the
PC has moved on two instructions. ~8 lines.

### 5. Measure it
Count branches and mispredicts, print the rate. Testbench work.

### Cosmetic
Lines 153 and 154 use `<=` inside an `always_comb`. Should be `=`.
Two compiler warnings, no effect on results.

---

## Open design decision (yours, not lookup)

**What state do the counters reset to?**

- All zeros = strongly not taken. Every loop pays two mispredicts warming up.
- Weakly taken = instant warm-up on loops, worse on branches that are
  usually not taken.

One-line change, measurable both ways once #5 exists.

---

## The number to beat

`t8_loop.s` runs its backward branch 30 times, taken every time.

- **Predict-not-taken (the original machine):** ~31 mispredicts, ~62 wasted cycles.
- **2-bit counter:** should be ~3 mispredicts. Two warming up on the loop-back
  branch, one on the loop exit.

The loop-exit branch does *not* improve. It's not taken 30 times and taken
once, and both predictors get exactly one mispredict on it. The entire win is
on the backward branch.

Those figures are derived, not measured. #5 is what turns them into real ones.

---

## Timing note for Vivado

The F-stage immediate extractor and 32-bit adder now sit on the fetch
critical path, which previously had almost nothing on it. Check WNS after
synthesis. Should be fine at 100 MHz, but confirm rather than assume.

---

## Reference

The 2-bit saturating counter is Smith's predictor:
James E. Smith, "A Study of Branch Prediction Strategies," ISCA 1981.

Harris & Harris cover branch prediction in the advanced microarchitecture
section of Chapter 7 (RISC-V edition). Worth reading before #1 through #4 —
this project is running ahead of that section.
