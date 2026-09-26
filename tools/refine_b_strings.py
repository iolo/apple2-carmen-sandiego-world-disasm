#!/usr/bin/env python3
"""Replace B loader's disk prompt bytes with explicit text strings."""

from reconstruct import ROOT, assemble, source_path


VARIANTS = {
    "disk1": (0x9BB2, 0x9BFA, "L9B83", "L9BFA"),
    "po": (0x9BAA, 0x9BF2, "L9B7B", "L9BF2"),
}


def refine(variant, start, end, preceding, following):
    path = source_path(variant, "B")
    source = path.read_text()
    if "; Disk insertion prompt" in source:
        print(f"{variant}/B strings already refined")
        return
    raw = (ROOT / "assets" / variant / "B.bin").read_bytes()
    region = raw[start - 0x9800:end - 0x9800]
    strings = region.split(b"\0")
    if strings[-1] or len(strings) != 5 or not all(x.isascii() for x in strings[:-1]):
        raise RuntimeError(f"{variant}/B: unexpected prompt strings")
    first = source.index(f"        jmp     {preceding}") + len(f"        jmp     {preceding}")
    last = source.index(f"\n{following}:", first)
    lines = ["", "", "        ; Disk insertion prompt"]
    for item in strings[:-1]:
        lines.append(f'        .asciiz "{item.decode("ascii")}"')
    source = source[:first] + "\n".join(lines) + source[last:]
    original = path.read_text()
    path.write_text(source)
    try:
        rebuilt = assemble(variant, "B", 0x9800)
    except RuntimeError:
        path.write_text(original)
        raise
    if rebuilt != raw:
        path.write_text(original)
        raise RuntimeError(f"{variant}/B prompt did not round-trip")
    print(f"{variant}/B: four prompt strings round-trip")


def main():
    for variant, args in VARIANTS.items():
        refine(variant, *args)


if __name__ == "__main__":
    main()
