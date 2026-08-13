# Memory hierarchy — plan

**Written:** 2026-08-12
**Starting:** 2026-08-13
**Target:** direct-mapped D-cache with a real miss penalty, measured.
**Budget:** ~half a month, with the MSU move and semester start inside it.

---

## The framing

**A cache only helps if something slow is behind it.**

`DataMem` today is a 64-word array that answers in one cycle, every time. Adding
a cache in front of that makes the machine *slower*: tag comparison on a path
that was already instant.

So this is not "add a cache." It is "build a realistic memory system, then add a
cache to cope with it." The problem has to be constructed before it can be
solved, and that is what makes this bigger than the chapter makes it look.

---

## Order of work

Steps are in dependency order. Step 2 is the whole risk.

### 1. Tag and branch — 5 minutes, do it first

```
git tag v1-predictor
git checkout -b cache
```

`master` stays the demoable machine. A tag beats a directory copy: history is
preserved, diffs work, and an abandoned attempt just never gets merged. Do not
copy the folder.

### 2. Multi-cycle stall infrastructure — the hard part

Today the only stall is `lwStall`, one cycle, driving exactly `StallF` and
`StallD`. There is no `StallE`, `StallM`, or `StallW`. **The execute stage
advances unconditionally every clock** — that property is also what makes the
mispredict counting in `tb.sv` exact, so revisit that instrumentation if E
starts stalling.

A cache miss stalls ~15 cycles and must freeze F, D, E and M together while
holding the M-stage instruction in place. That means an enable on every pipeline
register, plus re-verifying every stall/flush interaction.

**Test it with a fake stall, before any cache exists.** Write a generator that
asserts a stall for N cycles at an arbitrary point and run the regression. If
65/65 survives a stall injected anywhere in any program, the hard part is done
and the cache becomes plumbing.

Doing this after the cache makes every failure ambiguous: bad tag compare, or
the stall dropping an instruction? Two new things debugged through each other.

### 3. Slow main memory model

Multi-cycle latency, 10 to 20 cycles, valid/ready handshake. Behavioral, ~30
lines. Easy once step 2 exists.

### 4. Direct-mapped write-through D-cache

Tag array, valid bits, data array, hit compare. ~60 lines. Genuinely the easy
part. Write-through with no write allocate is the smallest thing that works;
no dirty bits, no writeback state machine.

### 5. Bigger DataMem and benchmarks with locality

Coupled to step 4: **the cache is only measurable once the working set exceeds
it.** A cache over the current 64 words reports a 100% hit rate and tells you
nothing.

Needs DataMem in the 1024+ word range and programs that stream through arrays
rather than touching a handful of addresses. More work than it sounds, and
`asm.py` may need attention.

### 6. Instrumentation

Hit rate, miss rate, AMAT, and a CPI that finally includes memory. Same pattern
as the existing per-PC branch counters in `tb.sv`. Harness work, mine.

---

## Explicitly out of scope

**No instruction cache.** The combinational `InstrMem` read is exactly what let
the branch predictor skip a BTB (instruction bits are valid in the same cycle as
the address). An I-cache makes fetch multi-cycle and reopens that whole
question. D-cache only.

**No set associativity as a plan.** Stretch goal after a direct-mapped cache is
measured, not part of the commitment.

---

## Decisions deferred to step 4

Write policy, cache size, block size, associativity. These get chosen better
once the stall path exists and there is something to measure. Do not spend
time on them tomorrow.

---

## Why this is worth doing

**Interview value.** Caches, associativity, write policies, the three Cs are the
most-asked computer architecture topics, not close.

**It connects to the CUDA work.** SGEMM tiling is a memory hierarchy problem:
tiles into shared memory to avoid DRAM traffic, register tiling to avoid
shared-memory traffic. Same idea one level up. "I built the cache in hardware
and measured the hit rate, and that's why the 8x8 tile hits 0.25 reads per
FFMA" is an unusual connection to be able to make.

**It makes the CPI honest.** 1.05 on T8 is unrealistic precisely because memory
is free right now.

What it will *not* do is make this processor faster in any real sense. The
slowness is self-inflicted. Say that plainly in the writeup rather than
claiming a speedup against a problem that was invented for the demo.

---

## Abort condition

Pick a date in advance. If step 2 has not converged by then, stop and don't
merge. The failure mode worth avoiding is not running out of time — it's a
half-finished stall redesign sitting on `master` in late September, two weeks
before Ignite applications.

`master` at `v1-predictor` is a complete, measured, working machine. It is
already a portfolio piece on its own.
