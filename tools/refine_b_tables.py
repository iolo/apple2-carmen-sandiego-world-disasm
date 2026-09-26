#!/usr/bin/env python3
"""Replace the B loader's mechanical tail with file dispatch tables."""

from pathlib import Path

from reconstruct import ROOT, assemble, source_path


LOAD = 0x9800
FILES = "cdefghijknopqrstu"
VARIANTS = {"disk1": 0x9C14, "po": 0x9C0C}


def refine(variant, table_start):
    source_file = source_path(variant, "B")
    source = source_file.read_text()
    binary = (ROOT / "assets" / variant / "B.bin").read_bytes()
    if "; Module index order:" in source:
        if assemble(variant, "B", LOAD) != binary:
            raise RuntimeError(f"{variant}/B: existing table source no longer round-trips")
        print(f"{variant}/B table already refined")
        return
    table = binary[table_start - LOAD:]
    low = table[:17]
    high = table[17:34]
    pages = table[34:51]
    names = table[51:]
    if len(names) != 51 or any(high_byte != (table_start + 51) >> 8 for high_byte in high):
        raise RuntimeError(f"{variant}/B: unexpected file dispatch table")
    addresses = {table_start + 51 + 3 * i: letter for i, letter in enumerate(FILES)}
    if any(names[3*i:3*i+3] != bytes((1, ord(letter), 0)) for i, letter in enumerate(FILES)):
        raise RuntimeError(f"{variant}/B: unexpected Pascal filenames")
    pointers = [low[i] | high[i] << 8 for i in range(17)]
    if any(address not in addresses for address in pointers):
        raise RuntimeError(f"{variant}/B: filename pointer leaves table")

    lines = [
        "; Filename pointers by module number. Each filename below is a",
        "; one-character Pascal string followed by a pad byte.",
        f"L{table_start:04X}:  .byte   " + ", ".join(f"<L{address:04X}" for address in pointers[:12]),
        f"L{table_start + 12:04X}:  .byte   " + ", ".join(f"<L{address:04X}" for address in pointers[12:]),
        f"L{table_start + 17:04X}:  .byte   " + ", ".join(f">L{address:04X}" for address in pointers),
        "; High byte of the first buffer used for each module.",
        f"L{table_start + 34:04X}:  .byte   " + ", ".join(f"${value:02X}" for value in pages),
        "; Module index order: " + ", ".join(addresses[address].upper() for address in pointers),
    ]
    for i, letter in enumerate(FILES):
        address = table_start + 51 + 3 * i
        lines.append(f"L{address:04X}:  .byte   $01, '{letter}', $00")
    original = source
    source = source[:source.index(f"L{table_start:04X}:")] + "\n".join(lines) + "\n"
    source_file.write_text(source)
    try:
        rebuilt = assemble(variant, "B", LOAD)
    except RuntimeError:
        source_file.write_text(original)
        raise
    if rebuilt != binary:
        source_file.write_text(original)
        raise RuntimeError(f"{variant}/B table did not round-trip")
    print(f"{variant}/B: 17 module filenames and buffer pages round-trip")


def main():
    for variant, table_start in VARIANTS.items():
        refine(variant, table_start)


if __name__ == "__main__":
    main()
