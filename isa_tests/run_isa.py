#!/usr/bin/env python3
"""Build and run the riscv-tests rv32ui suite on pipelined.sv.

Usage:  python3 isa_tests/run_isa.py [test ...] [--timeout N] [--verbose]

With no test names, every rv32ui test is run except the ones in SKIP.
Run from the repository root.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ISA = ROOT / "isa_tests"
VENDOR = ISA / "vendor" / "riscv-tests" / "isa"
BUILD = ISA / "build"
SIM = BUILD / "sim_isa"

CC = "riscv64-elf-gcc"
OBJCOPY = "riscv64-elf-objcopy"
CFLAGS = [
    "-march=rv32i", "-mabi=ilp32", "-nostdlib", "-nostartfiles",
    "-mno-relax", "-static",
    f"-I{ISA / 'env'}", f"-I{VENDOR / 'macros' / 'scalar'}",
    f"-Wl,-T,{ISA / 'env' / 'link.ld'}",
]

# fence_i needs Zifencei (self-modifying code through a unified memory);
# ma_data needs misaligned loads and stores. Neither is in scope.
SKIP = {"fence_i", "ma_data"}


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def build_sim() -> None:
    BUILD.mkdir(exist_ok=True)
    r = run(["iverilog", "-g2012", "-o", str(SIM),
             str(ISA / "tb_isa.sv"), str(ROOT / "processor" / "pipelined.sv")])
    if r.returncode != 0:
        sys.exit(f"iverilog failed:\n{r.stderr}")


def build_test(name: str) -> str | None:
    """Return an error string, or None on success."""
    src = VENDOR / "rv32ui" / f"{name}.S"
    elf = BUILD / f"{name}.elf"
    r = run([CC, *CFLAGS, str(src), "-o", str(elf)])
    if r.returncode != 0:
        return "compile: " + r.stderr.strip().splitlines()[-1]
    r = run([OBJCOPY, "-O", "verilog", "--verilog-data-width=4",
             "--only-section=.text", str(elf), str(BUILD / f"{name}.hex")])
    if r.returncode != 0:
        return "objcopy text: " + r.stderr.strip()
    data_bin = BUILD / f"{name}.data.bin"
    r = run([OBJCOPY, "-O", "binary", "--only-section=.data", str(elf), str(data_bin)])
    if r.returncode != 0:
        return "objcopy data: " + r.stderr.strip()
    r = run([sys.executable, str(ROOT / "C_test" / "split_data.py"),
             str(data_bin), str(BUILD / f"{name}.data")])
    if r.returncode != 0:
        return "split_data: " + r.stderr.strip()
    return None


def run_test(name: str, timeout: int, verbose: bool) -> tuple[str, str]:
    """Return (status, detail). SUSPECT = PASS reached, but a PC/instruction mispair was seen."""
    r = run(["vvp", "-n", str(SIM),
             f"+hex={BUILD / f'{name}.hex'}",
             f"+data={BUILD / f'{name}.data'}",
             f"+timeout={timeout}"])
    out = r.stdout
    if verbose:
        print(out, end="")
    (BUILD / f"{name}.log").write_text(out + r.stderr)
    if m := re.search(r"ISA PASS cycles=(\d+)", out):
        return "PASS", f"{int(m.group(1))} cycles"
    if m := re.search(r"ISA SUSPECT (.*)", out):
        return "SUSPECT", m.group(1)
    if m := re.search(r"ISA FAIL (.*)", out):
        return "FAIL", m.group(1)
    if m := re.search(r"ISA TIMEOUT (.*)", out):
        return "TIMEOUT", m.group(1)
    lines = (r.stderr or out).strip().splitlines()
    return "ERROR", lines[-1] if lines else "no output"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("tests", nargs="*")
    ap.add_argument("--timeout", type=int, default=200000)
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args()

    if args.tests:
        names = args.tests
    else:
        names = sorted(p.stem for p in (VENDOR / "rv32ui").glob("*.S")
                       if p.stem not in SKIP)

    build_sim()
    results: dict[str, tuple[str, str]] = {}
    print(f"=== riscv-tests rv32ui on pipelined.sv ({len(names)} tests) ===\n")
    for name in names:
        err = build_test(name)
        if err:
            results[name] = ("ERROR", err)
        else:
            results[name] = run_test(name, args.timeout, args.verbose)
        status, detail = results[name]
        print(f"  {name:<8} {status:<8} {detail}")

    passed = sum(1 for s, _ in results.values() if s == "PASS")
    suspect = sum(1 for s, _ in results.values() if s == "SUSPECT")
    print(f"\n=== {passed}/{len(names)} rv32ui tests passed ===")
    if suspect:
        print(f"=== {suspect} SUSPECT: reached PASS but Decode saw an instruction "
              f"paired with the wrong PC (see build/<test>.log) ===")
    if SKIP and not args.tests:
        print(f"=== skipped: {', '.join(sorted(SKIP))} ===")
    sys.exit(0 if passed == len(names) else 1)


if __name__ == "__main__":
    main()
