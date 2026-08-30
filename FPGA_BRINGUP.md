# FPGA Bring-Up

Notes from the first hardware bring-up of the core on the Nexys A7-100T, 2026-08-25.

Everything below is measured, not estimated. Two defects in the RTL were found by hardware that a 65/65 simulation regression did not catch, and the timing behavior of the core is characterized for the first time.

---

# 1. What Was Proven

| Claim | Evidence |
|---|---|
| The core runs on real silicon | `DONE` asserted, end of startup status HIGH |
| UART echo works end to end | 760 bytes sent, 760 returned, zero errors |
| Timing at 100 MHz is marginal | WNS ranges +0.217 ns to -0.242 ns depending on ROM contents |
| The critical path is stable | Operand register -> ALU carry chain -> stall enable, in every build |

The echo test is the strongest single result. Getting 760 bytes back byte-for-byte exercises the receiver, the status polling loop, `beq`, the MMIO decode, and the transmitter, in a closed loop against a host at 115200 baud.

---

# 2. Toolchain: `$readmemh` And The Silent Empty Build

The first build produced a bitstream that looked healthy and was completely hollow.

```
Slice LUTs        30 / 63400
Slice Registers   22 / 126800
WNS           +7.149 ns
```

22 flip-flops is exactly `Horizontal[10] + Vertical[10] + clkEnable[2]`. The VGA generator's counters were the only surviving logic in the design. The processor, transmitter, and receiver were all gone, and the enormous slack was meaningless because there was nothing left to time.

The cause was in the synthesis log:

```
CRITICAL WARNING: [Synth 8-4445] could not open $readmem data file 'memory.hex'
  ... pipelined.sv:313
WARNING: [Synth 8-3848] Net InstrMem in module/entity pipelined does not have driver
```

`pipelined.sv:313` does `$readmemh("memory.hex", InstrMem)` with a relative path. Synthesis could not resolve it, so `InstrMem` had no contents, every instruction read as a constant, and constant propagation consumed the core outward from the fetch stage. `VGAReg` is never written, so `BgColor` folds to a constant, so the output mux folds too.

Adding the hex with `add_files` is **not** sufficient. Vivado resolves that relative path against the synthesis run's working directory, `<proj>.runs/synth_1`. The fix is a pre-synthesis hook that copies the file there:

```tcl
set_property STEPS.SYNTH_DESIGN.TCL.PRE "<path>/pre_synth.tcl" [get_runs synth_1]
```

where `pre_synth.tcl` is one line:

```tcl
file copy -force "<root>/memory.hex" [file join [pwd] memory.hex]
```

**The lesson worth keeping:** a suspiciously small utilization report means the design was deleted, not that it is efficient. Check utilization before touching the board, every time. A hollow build programs successfully and asserts `DONE` exactly like a real one.

---

# 3. Defect 1: `DCache` Driven From Two `always_ff` Blocks

Implementation stopped before `opt_design` with **2048 DRC errors**, which is 64 words x 32 bits, every bit in the cache.

```
ERROR: [DRC MDRV-1] Multiple Driver Nets: Net processor/DCache[0][0][3]_128[0]
  has multiple drivers: DCache_reg[0][0][3][0]/Q, and DCache_reg[0][0][3][0]__0/Q
```

`DCache` was written from two separate `always_ff` blocks: the refill, and the write hit. Both conditions were correct and the two are mutually exclusive in time, which is why simulation was right and the benchmark numbers were real.

iverilog does not enforce SystemVerilog's single-driver rule on a `logic` variable. It schedules both nonblocking assignments and, since the conditions never fire in the same cycle, no conflict ever appears. Synthesis has no such freedom: a variable assigned in two always blocks becomes two physical register banks, so Vivado built `DCache_reg[...]` and `DCache_reg[...]__0`, tied both outputs to one net, and the DRC checker correctly refused it.

**Fix:** the write-hit assignment moved up into the same `always_ff` that owns the refill, so one block owns the array. Behavior is unchanged because the conditions were already mutually exclusive. Verified by `make` staying at 65/65 and `make cache` reproducing 2.12x / 2.85x / 2.13x / 6.17x exactly.

**The general lesson:** simulation passing says nothing about synthesizability. A construct can be perfectly well-defined in one and illegal in the other.

---

# 4. Defect 2: UART Receiver Sampled Bit 0 On The Bit Edge

The first echo test on hardware returned every byte, with two of 23 corrupted:

```
sent    : Hello from the Nexys A7
received: Hello from the Ndxys @7

'e' 0x65 -> 'd' 0x64
'A' 0x41 -> '@' 0x40
```

Both errors are **bit 0 cleared**, and nothing else was wrong. Frame count was exact, so the receiver detected all 23 start bits and the transmitter returned 23 well-formed frames. Losing only the first data bit, and only sometimes, is not a marginal-hardware signature. It points at one specific sampling instant.

## 4a. Root Cause

Two bugs compounding:

1. **`Count` was declared `logic [9:0]`**, holding 0 to 1023, but compared against `1301` in two places. That comparison can never be true. The intended 1.5 bit-time sample for the first data bit never happened.
2. **The index block advanced `Index` on `Count == 867` unconditionally**, without excluding `Index == 0`. So the first bit period ended one full bit time after `Busy`, which is exactly the boundary between the start bit and data bit 0.

The receiver was sampling the transition itself. When the sample won the race it read the correct bit, when it lost it read the start bit's 0, which is why every failure cleared bit 0 and why the same character `e` was correct at position 1 and wrong at position 16.

## 4b. Why Bits 1 Through 7 Survived

By accident. When `Index` advanced at 867, the counter did not reset that cycle, so it climbed to 1023, wrapped, and only then counted to 867 again. That made bit 1's period 1024 cycles instead of 868, which pushed every later sample about 156 cycles past its bit edge, roughly 18% into the bit. Marginal, but off the transition. The frame decoded because of a rollover that was never designed.

| Bit | Sample point, cycles from `Busy` | Ideal center | Position in bit |
|---|---|---|---|
| 0 | 868 | 1302 | exactly on the leading edge |
| 1 | 1892 | 2170 | 18% in |
| 2+ | +868 each | +868 each | 18% in |

## 4c. Fix

```
Count widened to 11 bits so 1301 is representable
Index advances on Count == 1301 when Index == 0, else on Count == 867
```

The two conditions must be mutually exclusive, `else if`, not two sequential `if`s, or the 867 branch still fires first during bit 0 and nothing changes.

Afterward the counter block and the index block agree on when a bit period ends. Samples land at 1301, 2169, and 3037 cycles from `Busy`, against ideal centers of 1302, 2170, and 3038. Dead center on every bit.

Note that during bit 0 the counter still passes through 867, so the sampling block writes a junk value into `Storage[0]` on the way past and overwrites it at 1301. Harmless, since `Data` is not read until the frame completes.

## 4d. Why Simulation Never Caught It

There is no testbench for the UART anywhere in the repo. `make` covers the processor, `make cache` covers the cache, `make vga` covers the generator. The receiver had never been exercised until it met a real host. The 65/65 was never claiming to cover it.

---

# 5. Static Timing

## 5a. Results Across Builds

Same RTL in every row. The only variable is the program in `memory.hex` and the implementation strategy.

| Build | ROM contents | Constraint | WNS | Failing endpoints |
|---|---|---|---|---|
| VGA, default strategy | `vgatest` | 10.00 ns | **+0.217 ns** | 0 / 11080 |
| Echo, default strategy | `echo` | 10.00 ns | -0.045 ns | 28 / 11142 |
| Echo, Performance_ExplorePostRoutePhysOpt | `echo` | 10.00 ns | -0.154 ns | 24 / 11142 |
| Echo, default strategy | `echo` | 10.50 ns | +0.137 ns | 0 / 11144 |
| Echo, repo `build.tcl` as committed | `echo` | 10.00 ns | -0.242 ns | 52 / 11142 |

The core is **marginal at 100 MHz on this part**. Whether it closes depends on what is in the instruction ROM, because different constants let synthesis fold away different logic, which changes placement, which changes wire lengths. The logic never changed. The geography did.

The post-route physical optimization strategy made timing *worse*, not better. On a design this close to the edge, the variance between strategies exceeds the violation being chased.

## 5b. The Critical Path

Stable across every build:

```
Source:      processor/A2E_reg[*]/C        (or A1E_reg[*])
Destination: processor/InstrD_reg[*]/CE    (or PCPlus4D_reg[*]/CE)
Data Path Delay: 9.404 ns  (logic 3.126 ns 33%, route 6.278 ns 67%)   @ 10.00 ns
Logic Levels: 15  (CARRY4=7 LUT3=1 LUT4=3 LUT5=1 LUT6=3)
```

Reading the cell chain: it starts at an operand register in Execute, passes through the forwarding mux into `RD2EI`, through the `ALUSrcBE` mux, down all seven CARRY4 blocks of the 32-bit ALU adder, and terminates at the **clock enable** of a Decode-stage pipeline register, which is a stall signal.

In plain terms: the design computes a full 32-bit addition and then uses that result to decide whether to freeze the pipeline, all within one cycle. `MemStall` depends on cache hit detection, which depends on the address, which is the ALU result. A control decision sitting downstream of an adder is the classic frequency limiter in a real core.

This is not a defect. It is a design choice with a measurable cost, and the cost is everything above roughly 100 MHz.

Between 67% and 73% of the path is routing rather than logic in every build, which is typical for a design with no floorplanning.

## 5c. On Fmax

A single relaxed build understates Fmax. Given a 10.5 ns target the router produced a 10.120 ns path; given 10.0 ns it produced 9.764 ns. Place and route optimizes to the constraint and then stops, so `1 / (period - WNS)` from one relaxed run is a lower bound, not a measurement. A real Fmax number requires tightening the constraint until it just fails.

Also worth recording: relaxing `create_clock` does not slow the board. `CLK100MHZ` is a fixed 100 MHz oscillator on pin E3. Running the core slower would take an MMCM, and that would break both the `868` baud divisor and the `/4` VGA clock enable, since both are hardcoded for 100 MHz.

The bitstream that missed timing by 154 ps still returned 760 bytes without error, because that WNS is quoted at the slow process corner with worst-case voltage and temperature, and a part on a desk has margin over that corner. Working in practice is not the same as closing timing.

## 5d. Ways To Close It

1. Let the tool try harder. Works at 45 ps, useless at 2 ns, and can backfire as it did here.
2. Lower the clock. Legitimate if the frequency actually closed is the one reported.
3. Cut the path with a register, at the cost of a cycle and a hazard-logic redesign.
4. Restructure so the stall decision does not depend on the ALU result in the same cycle. The real fix.

---

# 6. Utilization

Post-implementation, echo build, xc7a100tcsg324-1:

| Resource | Used | Available | % |
|---|---|---|---|
| Slice LUTs | 4480 | 63400 | 7.07 |
| Slice Registers | 2653 | 126800 | 2.09 |
| LUT as Memory | 748 | 19000 | 3.94 |
| Block RAM Tile | 0 | 135 | 0.00 |
| Bonded IOB | 18 | 210 | 8.57 |

The VGA build lands within 2% of these numbers. Zero block RAM: `InstrMem`, `RegFile`, `DataMem`, and `DCache` all inferred as distributed RAM in LUTs, which is what the 748 LUT-as-memory figure is.

---

# 7. Hardware Test Results

Host side is stdlib `termios` at 115200 8N1, one byte at a time, reading back between sends. The board's micro USB is a dual-channel FT2232H: channel A is the JTAG programmer, channel B is a USB serial bridge wired to `UART_TXD_IN` (C4) and `UART_RXD_OUT` (D4). No external hardware is needed for the echo demo.

| Test | Sent | Returned | Errors |
|---|---|---|---|
| Before receiver fix | 23 | 23 | 2, both bit 0 |
| After receiver fix | 23 | 23 | 0 |
| Stress, printable ASCII x8 | 760 | 760 | 0 |

The stress run covers every printable ASCII code, 0x20 through 0x7e, eight times, so every bit pattern including all cases where bit 0 is set.

---

# 8. Still Not Verified

1. VGA output has never been displayed. No VGA cable on hand. The generator's timing passes `make vga` in simulation and the design builds and programs, but no monitor has confirmed the bars.
2. Fmax is bounded, not measured. See 5c.
3. No hold-time analysis was examined beyond the summary reporting zero failing endpoints.
4. No on-board capture. An ILA would show real signals rather than simulated ones.
5. The processor has still never been checked against a golden model such as Spike.

---

# 9. Reproducing The Build

```bash
python3 asm.py uart/echo.s memory.hex      # or vga/vgatest.s
```

Then, from the Vivado Tcl console or `vivado -mode batch -source`:

```tcl
# file list, part xc7a100tcsg324-1, top.xdc as constraints
# plus the pre-synthesis hook from section 2, which is required
set_property STEPS.SYNTH_DESIGN.TCL.PRE "<path>/pre_synth.tcl" [get_runs synth_1]
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
open_run impl_1
report_utilization                                    # check this before programming
report_timing_summary -delay_type max -max_paths 3
```

Programming needs `open_hw_manager` / `connect_hw_server` / `open_hw_target` first. If the target is found but reports **no devices detected**, the board's power switch is off: the FT2232H is powered from USB and enumerates even when the board is not.

Board configuration is volatile. A power cycle clears it.

---

# 10. Authorship

| Mine | Tooling, built with AI assistance |
|---|---|
| The `DCache` single-driver fix in `pipelined.sv` | `build.tcl`, the pre-synthesis hook |
| The receiver sampling fix in `receiver.sv` | The host-side serial test harness |
| | Vivado driving, log analysis, and this write-up |

Both RTL defects in sections 3 and 4 were diagnosed jointly and fixed by me.
