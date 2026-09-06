#!/usr/bin/env python3
"""Split a flat little-endian data image across the core's four RAM banks."""

from __future__ import annotations

import argparse
from pathlib import Path


def split_banks(data: bytes) -> list[list[int]]:
    """Return words grouped by address[3:2], preserving row order."""
    padded = data + bytes((-len(data)) % 4)
    banks: list[list[int]] = [[], [], [], []]

    for byte_address in range(0, len(padded), 4):
        word = int.from_bytes(padded[byte_address : byte_address + 4], "little")
        bank = (byte_address >> 2) & 0b11
        banks[bank].append(word)

    return banks


def write_banks(data: bytes, output_prefix: Path) -> list[Path]:
    banks = split_banks(data)
    outputs: list[Path] = []

    for bank_number, words in enumerate(banks):
        output = output_prefix.parent / f"{output_prefix.name}{bank_number}.hex"
        contents = "".join(f"{word:08X}\n" for word in (words or [0]))
        output.write_text(contents)
        outputs.append(output)

    return outputs


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Split a binary .data section into DataMem0..DataMem3 hex files"
    )
    parser.add_argument("input", type=Path, help="flat binary produced by objcopy")
    parser.add_argument(
        "output_prefix",
        type=Path,
        help="output prefix; 'C_test/data' produces data0.hex through data3.hex",
    )
    args = parser.parse_args()

    write_banks(args.input.read_bytes(), args.output_prefix)


if __name__ == "__main__":
    main()
