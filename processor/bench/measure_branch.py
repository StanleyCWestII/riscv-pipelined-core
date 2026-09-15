"""Controlled prediction comparisons on temporary RTL copies.

All variants use the current registered fetch, caches, memory latency, and
regression programs. The source RTL is never edited. With no BTB, prediction
uses the existing post-fetch target adder (PCHold + decoded immediate).

The counters-only and current variants also differ in cold-target policy:
the current design uses backward-taken fallback on a BTB miss. Their delta
therefore measures the BTB plus that fallback, not the BTB alone.

The backward-only variant gives an equal-misprediction T8 comparison with
the current design, showing the benefit of earlier target availability.
The no-RAS variant suppresses return prediction; returns resolve in Execute.
It retains prediction of other branches/jumps and all return-stack storage.
"""

from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def assignment(text, name, expression):
    result, count = re.subn(
        r"assign " + re.escape(name) + r" = [^;]+;",
        "assign " + name + " = " + expression + ";",
        text,
    )
    if count != 1:
        raise RuntimeError(f"Expected one assignment to {name}, found {count}")
    return result


def run(command):
    result = subprocess.run(
        command, cwd=ROOT, capture_output=True, text=True, timeout=120
    )
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


def main():
    source = (ROOT / "processor/pipelined.sv").read_text()
    no_btb = assignment(source, "HitBuffer", "1'b0")
    fallback = "(InstrF[6:0] == 7'b1100011) && ~ClearInstr && ~StallF"
    variants = {
        "Not taken, no BTB": assignment(no_btb, "FallBackTaken", "1'b0"),
        "Always taken, no BTB": assignment(no_btb, "FallBackTaken", fallback),
        "Two-bit counters, no BTB": assignment(
            no_btb, "FallBackTaken", fallback + " && ~BranchState[PCHold[7:2]][1]"
        ),
        "Backward taken, no BTB": assignment(
            no_btb, "FallBackTaken", fallback + " && InstrF[31]"
        ),
        "Current, return prediction off": assignment(
            source,
            "PredictedF",
            "HitBuffer && ~isReturnBuffer[PCF[7:2]] && "
            "(isJumpBuffer[PCF[7:2]] || ~BranchState[PCF[7:2]][1])",
        ),
    }
    reset_assignment = "BranchState[i] <= WeaklyTaken;"
    if source.count(reset_assignment) != 1:
        raise RuntimeError("Expected exactly one predictor reset assignment")
    for state in ("StronglyTaken", "WeaklyNotTaken", "StronglyNotTaken"):
        variants[f"Current, reset {state}"] = source.replace(
            reset_assignment, f"BranchState[i] <= {state};"
        )
    variants["Current"] = source
    rows = []
    with tempfile.TemporaryDirectory(prefix="rv32-branch-") as directory:
        temporary = Path(directory)
        for index, (name, rtl) in enumerate(variants.items()):
            path = temporary / f"variant_{index}.sv"
            path.write_text(rtl)
            binary = temporary / f"sim_{index}"
            run([
                "iverilog", "-g2012", "-s", "tb", "-o", str(binary),
                "processor/tb.sv", str(path),
            ])
            output = run(["vvp", str(binary)])
            checks = re.search(r"=== (\d+)/(\d+) checks passed ===", output)
            if (
                not checks or checks[1] != checks[2]
                or "=== ALL TESTS PASSED ===" not in output
                or "FAIL" in output or "TIMEOUT" in output
            ):
                raise RuntimeError(f"{name}: invalid comparison\n{output}")
            values = []
            for test in ("T8", "T21", "T22"):
                line = next(
                    line for line in output.splitlines()
                    if line.strip().startswith(test + " ")
                )
                values.append(int(re.search(r"cycles\s+(\d+)", line)[1]))
                if test == "T8":
                    mispredicts = int(re.search(r"mispredicts\s+(\d+)", line)[1])
            rows.append((name, *values, mispredicts, f"{checks[1]}/{checks[2]} passed"))

    print("Same current caches and modeled memory latency in every row.")
    print("Cycles include cold-cache startup; parking loops are excluded.")
    print(f"{'Variant':32} {'T8 cycles':>9} {'T8 mispred':>10} {'T21 cycles':>10} {'T22 cycles':>10}  Regression")
    for name, t8, t21, t22, mispredicts, checks in rows:
        print(f"{name:32} {t8:9} {mispredicts:10} {t21:10} {t22:10}  {checks}")
    baseline = rows[1][1]
    current = rows[-1][1]
    print(f"\nT8 always-taken -> current: {baseline} -> {current} cycles; "
          f"{100 * (baseline - current) / baseline:.1f}% fewer cycles.")
    print("Two-bit/no-BTB -> current includes both BTB and cold-target fallback changes.")
    print("T8 contains no calls/returns. Use T21 for return-stack cycle savings.")


if __name__ == "__main__":
    main()
