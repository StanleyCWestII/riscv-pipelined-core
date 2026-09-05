#!/usr/bin/env python3
"""
Minimal RV32I-subset assembler for the pipelined processor.

Supports exactly the instructions pipelined.sv decodes:
    add sub sll slt sltu xor srl sra or and     (R-type, all ten)
    addi slti sltiu xori ori andi               (I-type)
    slli srli srai                              (I-type shift, 5-bit shamt)
    beq bne blt bge bltu bgeu                   (B-type, all six)
    lui auipc                                   (U-type, 20-bit upper immediate)
    lb lw                       (I-type loads)
    sw                          (S-type)
    beq                         (B-type)
    jal                         (J-type)
    jalr                        (I-type, rd, offset(rs1))
    nop                         (pseudo: addi x0, x0, 0)

Labels are supported:  "loop:" on its own line or before an instruction.
Branch/jump targets may be a label or a signed byte offset.

Usage:
    python3 asm.py program.s program.hex
"""

import re
import sys

R_FUNCT = {
    "add":  (0b0000000, 0b000),
    "sub":  (0b0100000, 0b000),
    "sll":  (0b0000000, 0b001),
    "slt":  (0b0000000, 0b010),
    "sltu": (0b0000000, 0b011),
    "xor":  (0b0000000, 0b100),
    "srl":  (0b0000000, 0b101),
    "sra":  (0b0100000, 0b101),
    "or":   (0b0000000, 0b110),
    "and":  (0b0000000, 0b111),
}

I_FUNCT = {
    "addi":  0b000,
    "slti":  0b010,
    "sltiu": 0b011,
    "xori":  0b100,
    "ori":   0b110,
    "andi":  0b111,
}

B_FUNCT = {
    "beq":  0b000,
    "bne":  0b001,
    "blt":  0b100,
    "bge":  0b101,
    "bltu": 0b110,
    "bgeu": 0b111,
}

# Shift-immediates are I-type in shape only. Bits [24:20] hold a 5-bit shift
# amount, and bits [31:25] carry the same shift-type field the R-type forms use.
# They are NOT a 12-bit signed immediate, so they get their own encoder.
SHIFT_I = {
    "slli": (0b0000000, 0b001),
    "srli": (0b0000000, 0b101),
    "srai": (0b0100000, 0b101),
}


def reg(tok):
    tok = tok.strip()
    m = re.fullmatch(r"x(\d+)", tok)
    if not m:
        raise ValueError(f"bad register {tok!r}")
    n = int(m.group(1))
    if not 0 <= n <= 31:
        raise ValueError(f"register out of range: {tok}")
    return n


def imm(tok):
    tok = tok.strip()
    return int(tok, 0)


def fits(val, bits):
    lo = -(1 << (bits - 1))
    hi = (1 << (bits - 1)) - 1
    if not lo <= val <= hi:
        raise ValueError(f"immediate {val} does not fit in {bits} signed bits")
    return val & ((1 << bits) - 1)


def enc_r(rd, rs1, rs2, name):
    f7, f3 = R_FUNCT[name]
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0b0110011


def enc_u(rd, val, opcode):
    """U-type. The operand is the 20-bit FIELD, not the final register value:
    `lui x1, 0x12345` puts 0x12345000 in x1."""
    if not -(1 << 19) <= val <= (1 << 20) - 1:
        raise ValueError(f"U-type immediate {val} does not fit in 20 bits")
    return ((val & 0xFFFFF) << 12) | (rd << 7) | opcode


def enc_shift_i(rd, rs1, shamt, f7, f3):
    if not 0 <= shamt <= 31:
        raise ValueError(f"shift amount {shamt} out of range 0..31")
    return (f7 << 25) | (shamt << 20) | (rs1 << 15) | (f3 << 12) | \
           (rd << 7) | 0b0010011


def enc_i(rd, rs1, val, f3, opcode):
    return (fits(val, 12) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | opcode


def enc_s(rs2, rs1, val, f3, opcode):
    v = fits(val, 12)
    return (((v >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (f3 << 12) | ((v & 0x1F) << 7) | opcode


def enc_b(rs1, rs2, val, f3, opcode):
    if val & 1:
        raise ValueError("branch offset must be even")
    v = fits(val, 13)
    return (((v >> 12) & 1) << 31) | (((v >> 5) & 0x3F) << 25) | (rs2 << 20) | \
           (rs1 << 15) | (f3 << 12) | (((v >> 1) & 0xF) << 8) | \
           (((v >> 11) & 1) << 7) | opcode


def enc_j(rd, val, opcode):
    if val & 1:
        raise ValueError("jump offset must be even")
    v = fits(val, 21)
    return (((v >> 20) & 1) << 31) | (((v >> 1) & 0x3FF) << 21) | \
           (((v >> 11) & 1) << 20) | (((v >> 12) & 0xFF) << 12) | (rd << 7) | opcode


MEMREF = re.compile(r"(-?\w+)\s*\(\s*(x\d+)\s*\)")


def parse(text):
    """Pass 1: strip comments, collect labels, return [(addr, mnemonic, args)]."""
    labels = {}
    items = []
    addr = 0
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#")[0].strip()
        while True:
            m = re.match(r"^([A-Za-z_]\w*)\s*:\s*", line)
            if not m:
                break
            labels[m.group(1)] = addr
            line = line[m.end():].strip()
        if not line:
            continue
        parts = line.split(None, 1)
        mnem = parts[0].lower()
        args = [a.strip() for a in parts[1].split(",")] if len(parts) > 1 else []
        items.append((addr, mnem, args, lineno))
        addr += 4
    return labels, items


def target(tok, labels, here):
    """Resolve a branch/jump operand to a PC-relative byte offset."""
    tok = tok.strip()
    if tok in labels:
        return labels[tok] - here
    return int(tok, 0)


def assemble(text):
    labels, items = parse(text)
    words = []
    for addr, mnem, args, lineno in items:
        try:
            if mnem == "nop":
                w = enc_i(0, 0, 0, 0b000, 0b0010011)
            elif mnem in R_FUNCT:
                w = enc_r(reg(args[0]), reg(args[1]), reg(args[2]), mnem)
            elif mnem in SHIFT_I:
                f7, f3 = SHIFT_I[mnem]
                w = enc_shift_i(reg(args[0]), reg(args[1]), imm(args[2]), f7, f3)
            elif mnem in I_FUNCT:
                w = enc_i(reg(args[0]), reg(args[1]), imm(args[2]),
                          I_FUNCT[mnem], 0b0010011)
            elif mnem == "jalr":
                m = MEMREF.fullmatch(args[1])
                if not m:
                    raise ValueError("jalr needs offset(reg)")
                w = enc_i(reg(args[0]), reg(m.group(2)), imm(m.group(1)),
                          0b000, 0b1100111)
            elif mnem in ("lb", "lw"):
                m = MEMREF.fullmatch(args[1])
                if not m:
                    raise ValueError(f"{mnem} needs offset(reg)")
                w = enc_i(reg(args[0]), reg(m.group(2)), imm(m.group(1)),
                          0b000 if mnem == "lb" else 0b010, 0b0000011)
            elif mnem == "sw":
                m = MEMREF.fullmatch(args[1])
                if not m:
                    raise ValueError("sw needs offset(reg)")
                w = enc_s(reg(args[0]), reg(m.group(2)), imm(m.group(1)),
                          0b010, 0b0100011)
            elif mnem == "lui":
                w = enc_u(reg(args[0]), imm(args[1]), 0b0110111)
            elif mnem == "auipc":
                w = enc_u(reg(args[0]), imm(args[1]), 0b0010111)
            elif mnem in B_FUNCT:
                off = target(args[2], labels, addr)
                w = enc_b(reg(args[0]), reg(args[1]), off,
                          B_FUNCT[mnem], 0b1100011)
            elif mnem == "jal":
                off = target(args[1], labels, addr)
                w = enc_j(reg(args[0]), off, 0b1101111)
            else:
                raise ValueError(f"unsupported mnemonic {mnem!r}")
        except Exception as e:
            raise SystemExit(f"line {lineno}: {raw_of(text, lineno)}\n  error: {e}")
        words.append(w)
    return words


def raw_of(text, lineno):
    return text.splitlines()[lineno - 1].strip()


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    src = open(sys.argv[1]).read()
    words = assemble(src)
    if len(words) > 64:
        raise SystemExit(f"program is {len(words)} words; InstrMem holds 64")
    # Pad to the full 64-word InstrMem with "beq x0, x0, 0", a branch to itself.
    # A runaway PC then parks instead of wrapping around and re-running the
    # program from the top, and $readmemh stops warning about a short file.
    park = enc_b(0, 0, 0, 0b000, 0b1100011)
    with open(sys.argv[2], "w") as f:
        for w in words:
            f.write(f"{w:08x}\n")
        for _ in range(64 - len(words)):
            f.write(f"{park:08x}\n")
    print(f"{sys.argv[1]} -> {sys.argv[2]}  ({len(words)} instructions, padded to 64)")


if __name__ == "__main__":
    main()
