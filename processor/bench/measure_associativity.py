"""Compare 1/2/4 usable ways with eight sets and 16-word lines.

Temporary RTL copies disable unused hit signals and restrict victim selection.
The two-way variant uses the existing pair-0 recency bit for exact two-way LRU.
The four-way variant is unchanged. Usable capacity varies: 512 B, 1 KiB, 2 KiB.
These are simulation comparisons, not synthesis area/timing measurements.
"""

from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def replace_once(text, pattern, replacement):
    text, count = re.subn(pattern, lambda _: replacement, text, flags=re.DOTALL)
    if count != 1:
        raise RuntimeError(f"Expected one match for {pattern!r}, found {count}")
    return text


def run(command):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    if re.search(r"FAIL|TIMEOUT|DID NOT FINISH|FATAL|ERROR", result.stdout):
        raise RuntimeError(result.stdout)
    return result.stdout


def variant(source, ways):
    if ways == 4:
        return source
    for way in range(ways, 4):
        source = replace_once(source, rf"assign DHit{way} = [^;]+;", f"assign DHit{way} = 1'b0;")
    victim = "2'b00" if ways == 1 else "{1'b0, ~LRU[ALUResultM[8:6]][1]}"
    return replace_once(
        source, r"// Victim logic\s+always_comb.*?(?=always_ff)",
        f"// Restricted replacement for the {ways}-way measurement.\nassign Victim = {victim};\n\n",
    )


def checked_bench():
    bench = (ROOT / "processor/tb_cache.sv").read_text()
    # Run only cached cases. The forced-miss baseline is not an associativity variant.
    start = bench.index('        $display("=== same programs,')
    end = bench.index("        $finish;", start)
    bench = bench[:start] + bench[end:]
    checks = """
            case (bi)
                0: if (dut.RegFile[11] !== 32'd32640) $fatal(1, "B1 sum mismatch");
                1: if (dut.RegFile[11] !== 32'd32512) $fatal(1, "B2 sum mismatch");
                2: if (dut.RegFile[11] !== 32'd2095104) $fatal(1, "B3 sum mismatch");
                3: begin
                    if (dut.RegFile[5] !== 32'd0 || dut.RegFile[6] !== 32'd128 ||
                        dut.RegFile[7] !== 32'd256 || dut.RegFile[20] !== 32'd0)
                        $fatal(1, "B4 result mismatch");
                end
                4: begin
                    for (int word_addr = 0; word_addr < 256; word_addr++) begin
                        if (architectural_word(word_addr) !== 32'(word_addr * 4))
                            $fatal(1, "B5 store mismatch at word %0d", word_addr);
                    end
                end
            endcase
            $display("RESULT_CHECK B%0d PASS", bi + 1);
"""
    helper = """
    function automatic logic [31:0] architectural_word(input int unsigned word_addr);
        case (word_addr[1:0])
            0: architectural_word = dut.DataMem0[word_addr >> 2];
            1: architectural_word = dut.DataMem1[word_addr >> 2];
            2: architectural_word = dut.DataMem2[word_addr >> 2];
            3: architectural_word = dut.DataMem3[word_addr >> 2];
        endcase
        for (int way = 0; way < 4; way++)
            if (dut.DValid[word_addr[6:4]][way] === 1'b1 &&
                dut.DTag[word_addr[6:4]][way] === word_addr[13:7])
                architectural_word = dut.DCache[word_addr[6:4]][way][word_addr[3:0]];
    endfunction
"""
    bench = replace_once(bench, r"    task automatic run_bench", helper + "\n    task automatic run_bench")
    return replace_once(bench, r"            hitrate =", checks + "\n            hitrate =")


def main():
    source = (ROOT / "processor/pipelined.sv").read_text()
    rows = {}
    with tempfile.TemporaryDirectory(prefix="rv32-assoc-") as directory:
        temporary = Path(directory)
        bench = temporary / "tb_cache_checked.sv"
        bench.write_text(checked_bench())
        for ways in (1, 2, 4):
            rtl = temporary / f"ways_{ways}.sv"
            rtl.write_text(variant(source, ways))
            binary = temporary / f"regression_{ways}"
            run(["iverilog", "-g2012", "-s", "tb", "-o", str(binary), "processor/tb.sv", str(rtl)])
            regression = run(["vvp", str(binary)])
            checks = re.search(r"=== (\d+)/(\d+) checks passed ===", regression)
            if not checks or checks[1] != checks[2] or "=== ALL TESTS PASSED ===" not in regression:
                raise RuntimeError(regression)
            binary = temporary / f"cache_{ways}"
            run(["iverilog", "-g2012", "-s", "tb_cache", "-o", str(binary), str(bench), str(rtl)])
            output = run(["vvp", str(binary)])
            parsed = re.findall(
                r"^\s*(B[1-5] .+?)\s+(\d+)\s+(\d+)\s+(\d+)\s+([\d.]+)%\s+(\d+)\s+([\d.]+)\s+(\d+)\s+(\d+)\s*$",
                output, re.MULTILINE,
            )
            if len(parsed) != 5 or output.count("RESULT_CHECK") != 5:
                raise RuntimeError(output)
            rows[ways] = parsed
            print(f"{ways}-way: {8 * ways * 64} usable bytes; {checks[1]}/{checks[2]} regression; B1-B5 result checks passed")

    print("\nEight sets and 16-word lines in every variant. Capacity is NOT held constant.")
    print("Same current instructions, I-cache, predictor, write policy, and modeled memory delay.")
    print("\nBenchmark             1-way cycles/hit    2-way cycles/hit    4-way cycles/hit")
    for index in range(5):
        print(f"{rows[4][index][0]:20}" + "".join(
            f" {int(rows[ways][index][7]):8d} / {rows[ways][index][4]:>5}%" for ways in (1, 2, 4)
        ))
    print("\nB4: three words (12 bytes), all at set index zero in every variant.")
    print("Ways   Accesses   Hits   Misses   AMAT   Cycles   Speedup vs 1-way")
    for ways in (1, 2, 4):
        _, accesses, hits, misses, _, _, amat, cycles, _ = rows[ways][3]
        speedup = int(rows[1][3][7]) / int(cycles)
        print(f"{ways:4d} {int(accesses):10d} {int(hits):6d} {int(misses):8d} {float(amat):6.2f} {int(cycles):8d} {speedup:17.2f}x")


if __name__ == "__main__":
    main()
