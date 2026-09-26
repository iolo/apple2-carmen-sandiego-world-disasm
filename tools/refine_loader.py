#!/usr/bin/env python3
"""Mark confirmed loader text as data in both ca65 listings."""

import json
from pathlib import Path

from reconstruct import ROOT, assemble, source_path


LOAD = 0x2000


def readable_data(data, start):
    lines = [f"L{start:04X}:  ; ProDOS parameter bytes and NUL terminated loader messages"]
    offset = 0
    pending = bytearray()

    def flush():
        if pending:
            lines.append("        .byte   " + ", ".join(f"${byte:02X}" for byte in pending))
            pending.clear()

    while offset < len(data):
        end = offset
        while end < len(data) and 32 <= data[end] < 127:
            end += 1
        if end - offset >= 4 and end < len(data) and data[end] == 0:
            flush()
            value = data[offset:end].decode("ascii")
            lines.append(f"        ; ${start + offset:04X}")
            lines.append(f"        .asciiz {json.dumps(value)}")
            offset = end + 1
        else:
            pending.append(data[offset])
            offset += 1
    flush()
    return "\n".join(lines) + "\n"


def refine(variant, start, end):
    target = source_path(variant, "WORLD.SYSTEM")
    source = target.read_text()
    if f"L{start:04X}:  ; ProDOS parameter bytes" in source:
        print(f"{variant} loader already refined")
        return
    raw = (ROOT / "assets" / variant / "WORLD.SYSTEM.bin").read_bytes()
    original = "        sta     $C008\n        .byte   $AD\nL2044:  .byte   $82\n        cpy     #$A9\n        brk\n"
    corrected = "        sta     $C008\n        lda     $C082\n        lda     #$00\n"
    if source.count(original) != 1:
        raise RuntimeError("Expected loader instruction sequence not found")
    source = source.replace(original, corrected)
    first = source.index(f"L{start:04X}:")
    last = source.index(f"\nL{end:04X}:", first)
    source = (source[:first] + readable_data(raw[start - LOAD:end - LOAD], start)
              + source[last + 1:])
    original = target.read_text()
    target.write_text(source)
    try:
        rebuilt = assemble(variant, "WORLD.SYSTEM", LOAD)
    except RuntimeError:
        target.write_text(original)
        raise
    if rebuilt != raw:
        target.write_text(original)
        raise RuntimeError("Refined loader does not round-trip")
    print(f"refined {variant}/WORLD.SYSTEM: strings and interrupted instructions round-trip")


def main():
    refine("disk1", 0x238A, 0x246E)
    refine("po", 0x240A, 0x24EE)


if __name__ == "__main__":
    main()
