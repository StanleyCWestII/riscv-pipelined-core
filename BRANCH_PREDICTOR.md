# Branch Predictor, BTB, and RAS

## 1. Overview

The branch prediction logic is split into three parts: the two-bit branch predictor, branch target buffer (BTB), and return address stack (RAS). The predictor decides whether a conditional branch should be taken. The BTB holds destinations from previous branches and jumps so Fetch can use them before the instruction arrives. The RAS holds return addresses from function calls.

---

## 2. The Branch Predictor

The predictor consists of sixty-four two-bit counters, stored in `BranchState`. Each counter has four possible states:

```
00 = StronglyTaken
01 = WeaklyTaken
10 = WeaklyNotTaken
11 = StronglyNotTaken
```

The extra bit lets a strong prediction survive one wrong guess. If a branch is taken, its counter moves one step toward 00. If it isn't taken, the counter moves one step toward 11. Once it reaches either end, it stays there until the outcome changes. Reset sets every counter to `WeaklyTaken`.

Fetch indexes into the counters using `PCF[7:2]`. The bottom two address bits are dropped because instructions are four-byte aligned, and the remaining six bits select one of sixty-four entries. Different instructions can share an entry if these bits match. For example, addresses 256 bytes apart use the same counter. There are no tags in the counter table to tell them apart.

To get the prediction, Fetch reads `~BranchState[PCF[7:2]][1]`. Only the upper bit is needed because both taken states start with 0 and both not-taken states start with 1. The inversion makes a taken prediction come out as 1.

However, the counter only controls `PredictedF` when there is a BTB hit. A hit marked as a jump predicts taken regardless of the counter. On a miss, `PredictedF` is zero, and the backward-branch fallback described below can still make a later prediction.

When the branch reaches Execute, `BranchTaken` holds its actual outcome. It comes from the comparison selected by `Funct3E`: equal, not equal, signed less than, signed greater than or equal, unsigned less than, or unsigned greater than or equal. These comparisons use the forwarded operands.

`BranchNextState` uses that outcome to choose the counter's next value. While `BranchE` is asserted, the counter at `BranchState[PCE[7:2]]` is updated on the clock. `PCE` is used here because Fetch has moved on to a different address.

The counter update does not check `StallE`. If a cache stall holds a branch in Execute, that branch can update its counter more than once.

---

## 3. The Branch Target Buffer

Instruction fetch is registered, so the instruction arrives after its address has been presented. Waiting for its bits before calculating a branch destination adds a delay. The BTB avoids that wait for branches and jumps it has already seen by storing their destinations.

Like the predictor, the BTB has sixty-four entries indexed by `PCF[7:2]`. Each entry contains five signals:

1. `ValidBuffer`: one bit, tells whether the entry has been filled.
2. `TagBuffer`: eight bits, holds the instruction address's `[15:8]` bits.
3. `TargetBuffer`: thirty-two bits, holds the destination address.
4. `isJumpBuffer`: one bit, tells whether the entry is an unconditional jump.
5. `isReturnBuffer`: one bit, tells whether the entry is a recognized return.

`HitBuffer` checks that the selected entry is valid and its tag matches `PCF[15:8]`. This makes the BTB direct-mapped: each address has one possible location. If another instruction with the same index but a different tag gets written there, it replaces the old entry. Address bits above bit 15 aren't checked, which matches the current 64 KiB instruction-memory range.

Reset clears the valid bits, tags, targets, and jump flags. `isReturnBuffer` isn't explicitly reset, but an invalid entry can't produce a hit. The return flag is assigned when the entry is filled.

### 3a. Updating The Buffer

The BTB gets updated in Execute for taken conditional branches, direct jumps, and recognized returns. `jal` means jump and link and uses a direct destination. `jalr` means jump and link register and calculates its destination from a register plus an immediate. Register-indirect jumps only get inserted if they match the return detector described in Section 4.

When an entry is written, `PCE[7:2]` selects the location. `PCE[15:8]` becomes the tag, `PCTargetE` becomes the stored destination, and `JumpE` and `isReturnE` become the two flags. The valid bit is set to 1.

A not-taken branch doesn't fill the BTB or clear an existing entry. Like the counter update, the BTB update has no `StallE` check, so a held instruction can repeat the write.

### 3b. Using The Buffer

If `HitBuffer` is set and Fetch isn't stalled, `isBranchF` is set. Despite its name, this signal includes cached jumps and returns. It doesn't decode the current instruction's opcode.

`PredictedF` then checks whether the entry is a jump or the counter predicts taken. If either is true, the next-address mux can use the prediction. Regular branches and jumps use `TargetBuffer`. Entries marked as returns use the RAS instead.

### 3c. The Fallback

If the BTB misses, a backward conditional branch can still be predicted once `InstrF` arrives. This is handled by `FallBackTaken`, which checks five things:

1. `InstrF[6:0]` is `1100011`, the conditional-branch opcode.
2. `HitBufferHold` is zero, so this instruction's lookup missed.
3. `InstrF[31]` is one, meaning the branch offset is negative.
4. `ClearInstr` is zero.
5. Fetch isn't stalled.

The destination is calculated in `PCTargetF` by adding the reconstructed, sign-extended branch immediate to `PCHold`. It uses `PCHold` because that is the address belonging to `InstrF`; `PCF` has already moved ahead.

This gives backward branches a taken prediction on their first encounter. Forward branches with no BTB entry continue sequentially. A first-time direct jump or return waits until Execute because this fallback only handles conditional branches.

---

## 4. The Return Address Stack

A function can be called from several different locations. That means the same return instruction can have a different destination each time, which a single stored BTB target can't account for. The RAS handles this by remembering the address after each call.

The stack contains eight thirty-two-bit entries in `ReturnAdr`. `ReturnAdrPtr` is a three-bit pointer to the next position to write. Reset clears the pointer and all eight entries.

### 4a. Calls

When `JumpE` is set, `A3E` is 1, and Execute isn't stalled, the stack writes `PCPlus4E` into `ReturnAdr[ReturnAdrPtr]`. It then increments the pointer. `PCPlus4E` is the address of the instruction immediately after the call.

This recognizes both direct and register-indirect jumps that write `x1`, the conventional return-address register. A call that writes the alternate link register `x5` does not push onto this stack.

### 4b. Returns

`isReturnE` checks for a register-indirect jump that reads `x1` and writes `x0`, the fixed-zero register. The usual return instruction, `jalr x0, 0(x1)`, matches this condition. The detector doesn't check the immediate, so other offsets from `x1` match too.

Once that instruction has a BTB entry marked as a return, Fetch predicts its destination from the stack. `ReturnAdrTop` is `ReturnAdrPtr - 3'd1`, and `PredictedAdrF` reads `ReturnAdr[ReturnAdrTop]`.

When Fetch uses that prediction and isn't stalled, the pointer is decremented. This is the pop operation. It happens when the return is predicted, rather than when the return reaches Execute. If a return misses the BTB, it resolves in Execute without popping the stack.

The push and pop are in the same `if`/`else if` block. A call pushing in Execute takes priority over a return popping in Fetch if both happen together.

### 4c. Incorrect Return Addresses

The predicted address travels through `PredictedAdrHold`, `PredictedAdrD`, and `PredictedAdrE`. When a predicted return reaches Execute, its predicted address is compared with `PCTargetE`. If they differ, the processor redirects to the actual destination.

The three-bit pointer wraps when it goes past either end. There is no empty/full check, and a redirect doesn't restore earlier stack contents or the pointer. The return-address comparison handles an incorrect prediction, but it doesn't repair the stack itself.

---

## 5. Moving And Checking The Prediction

### 5a. The Pipeline Registers

Since instruction fetch is registered, the prediction has to be held alongside the instruction it belongs to. `PredictedF` goes through `PredictedHold`, then `PredictedD`, then `PredictedE`. The instruction address follows the same progression through `PCHold`, `PCD`, and `PCE`.

The predicted return address follows this path too. `HitBufferHold` remembers whether the fetched instruction had a BTB hit, which is needed for the fallback. `isBranchF` is also carried through Hold, Decode, and Execute, although the actual recovery and update logic uses the decoded `BranchE` and `JumpE` signals.

The Fetch values are held when `StallF` is set. Decode and Execute use `StallD` and `StallE` for their own registers. When the fallback fires, Decode sets both `PredictedD` and `isBranchD` so Execute knows the branch was predicted taken.

### 5b. The Next Address

`PCSrcE` controls the mux for `PCFNext`. It has four values:

1. `00`: continue sequentially using `PCPlus4F`.
2. `01`: correct the address using the result from Execute.
3. `10`: use the BTB target, or the RAS address if the entry is a return.
4. `11`: use `PCTargetF` for the backward-branch fallback.

The priority is Execute correction first, then the BTB prediction, then the fallback, then the sequential address.

`MisPredict` is `BranchTaken ^ PredictedE`. If a conditional branch's actual outcome differs from its prediction, this becomes 1. Execute also requests a correction when a jump wasn't predicted taken, or when a predicted return has the wrong destination. Those two jump checks are separate from `MisPredict`.

For an actually not-taken branch, recovery selects `PCPlus4E`. Otherwise it selects `PCTargetE`. Direct branches and jumps calculate that target from `PCE + ImmExtE`. Register-indirect jumps add the forwarded register value to the immediate and clear the destination's bottom bit. The predicted-address comparison is only done for recognized returns.

### 5c. Clearing The Wrong Instructions

An Execute correction flushes Decode and Execute through `FlushD` and `FlushE`, provided neither cache is stalling. This removes the younger instructions that came from the wrong path. Cache stalls hold the pipeline and delay the correction until it can advance.

There can also be another wrong-path instruction in the registered fetch path. `ClearInstr` is set after an Execute correction or fallback redirect so that instruction gets cleared before Decode accepts it. The flag stays set until Fetch can advance. Normal BTB predictions don't set it.

`RetInstr` handles the initial fetch delay. It starts at zero, keeps Decode flushed, and becomes one when the first unstalled instruction read occurs. Its name means an instruction has returned from memory, not that a function is returning.

---

## 6. Benchmarks

Measured September 12, 2026, using Icarus Verilog 13.0. Run `make branch` for the comparisons and `make all` for the current regression.

`processor/bench/measure_branch.py` makes temporary copies of the processor with different prediction settings. Each copy runs the same twenty-two programs and 176 checks. Registered fetch, both caches, and modeled memory latency are kept the same in every comparison.

Cycles include cold-cache startup and stop when the final parking instruction first reaches Execute. The parking loop's continued execution is excluded. Mispredict counts only include conditional branches, not incorrect jump or return destinations. Branches held by cache stalls aren't counted again on each stalled cycle.

### 6a. Prediction Comparisons

| Machine | T8 Cycles | T8 Mispredicts | T21 Cycles | T22 Cycles | Checks |
|---|---|---|---|---|---|
| Not Taken, No BTB | 263 | 31 | 97 | 55 | 176/176 |
| Always Taken, No BTB | 291 | 30 | 97 | 55 | 176/176 |
| Two-bit Counters, No BTB | 206 | 2 | 97 | 55 | 176/176 |
| Backward Taken, No BTB | 203 | 1 | 97 | 55 | 176/176 |
| Current, Return Prediction Off | 174 | 1 | 97 | 55 | 176/176 |
| Current | 174 | 1 | 91 | 55 | 176/176 |

Without the BTB, taken predictions use the immediate adder after the instruction arrives. With return prediction off, the stack still exists and calls still push, but Fetch doesn't predict entries marked as returns.

The two-bit counters reduce T8 from 291 to 206 cycles compared with always taken on the same no-BTB path. That's 85 cycles saved, or 29.2%. The full current design takes 174 cycles, which is 40.2% fewer than always taken.

Backward taken without the BTB and the current design both have one mispredict on T8, but the current design saves another 29 cycles, going from 203 to 174. This shows the benefit of getting the destination earlier on this loop. The direction policies also differ, so this isn't a general isolated BTB measurement. Likewise, the 206-to-174 comparison changes both the BTB and the fallback policy.

### 6b. The Test Programs

T8, `processor/tests/t8_loop.s`, contains two branch sites:

| Address | Behavior | Executions | Current Mispredicts |
|---|---|---|---|
| `0x14` | Forward exit branch, not taken 30 times and taken once | 31 | 1 |
| `0x18` | Backward loop branch, taken 30 times | 30 | 0 |

The exit branch doesn't get a BTB entry during its not-taken iterations. It continues sequentially until the final taken outcome causes a correction. The backward branch uses the fallback the first time, then uses its stored BTB target.

T21, `processor/tests/t21_call.s`, calls the same function from different locations and includes a nested call. The same return instruction must go to different destinations. Return prediction reduces this test from 97 to 91 cycles, saving six cycles, or 6.2%. All 5/5 checks pass. The outer function's final `jalr x0, 0(x2)` uses a saved address in `x2`, so that particular return isn't recognized by the RAS. T8 has no calls or returns and doesn't measure the stack's benefit.

T22, `processor/tests/t22_fakeret.s`, writes `x1` through arithmetic instead of a call. A repeated `jalr x0, 0(x1)` fills the BTB, then predicts an incorrect stack address on a later execution. Execute must catch the mismatch and redirect. It takes 55 cycles and passes 4/4 checks with return prediction either on or off. This test checks recovery rather than speedup.

The full current regression passes 176/176 checks and reports 77 conditional branches with 11 mispredicts, excluding parking loops. These are program-result checks rather than exhaustive tests of every predictor or stack state. The testbench's printed "wasted cycles" is just the mispredict count multiplied by three, not a separate measurement of all stall cycles.

### 6c. Reset State

Only the counter's initial state changes in this comparison. The BTB, fallback, RAS, and caches remain enabled.

| Reset State | T8 Cycles | T8 Mispredicts | T21 Cycles | T22 Cycles | Checks |
|---|---|---|---|---|---|
| StronglyTaken | 174 | 1 | 91 | 55 | 176/176 |
| WeaklyTaken, Current | 174 | 1 | 91 | 55 | 176/176 |
| WeaklyNotTaken | 174 | 1 | 91 | 55 | 176/176 |
| StronglyNotTaken | 177 | 2 | 91 | 55 | 176/176 |

WeaklyTaken is still the reset state, but it ties two other states on these tests. On a cold BTB miss, Fetch follows the fallback policy rather than using the initial counter value directly.

The older 195-to-139-cycle result and 1.05 cycles per instruction came from the combinational-fetch version. The comparisons above use the current registered fetch and memory delays.

---

## 7. Where Everything Is

All line numbers are in `processor/pipelined.sv`.

| Logic | Lines |
|---|---|
| Predictor, BTB, and RAS declarations | 125–147 |
| Mispredict detection and redirect priority | 246–256 |
| Counter states, reset, and update | 258–278 |
| BTB reset and update | 280–299 |
| RAS reset, push, and pop | 301–319 |
| Counter transitions | 321–332 |
| PC and hold register | 526–533 |
| ClearInstr | 535–540 |
| Sequential addresses, stack top, and next-address mux | 542–564 |
| Backward fallback condition | 566 |
| Registered fetch and RetInstr | 568–581 |
| BTB lookup, prediction, and fallback target | 583–595 |
| Prediction hold registers | 597–610 |
| Fetch-to-Decode register | 616–637 |
| Decode-to-Execute register | 697–746 |
| Actual target and return detection | 748–756 |
| Forwarded operands | 767–791 |
| Branch comparisons | 815–825 |
| Stalls and flushes | 1159–1169 |

## 8. References

James E. Smith, "A Study of Branch Prediction Strategies," ISCA 1981, describes two-bit saturating-counter prediction. Harris & Harris cover branch prediction in Chapter 7 of *Digital Design and Computer Architecture, RISC-V Edition*.
