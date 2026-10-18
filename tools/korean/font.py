"""Extract exact BDF pixels into eight Apple II seven-bit scanlines.

Never rasterize a scalable substitute or silently clip a missing/tall glyph.
The eight-row cell has seven rows above the baseline and one below it.
"""

from .common import ASSETS, read_json, sha256


def load_bdf():
    directory = ASSETS / "font"
    source = read_json(directory / "source.json")
    for name, expected in source["files"].items():
        if sha256((directory / name).read_bytes()) != expected:
            raise ValueError(f"Pinned font input changed: {name}")
    glyphs = {}
    for block in (directory / "GalmuriMono7.bdf").read_text().split("STARTCHAR ")[1:]:
        attributes = {}
        lines = block.splitlines()
        for line in lines[1:]:
            key, _, value = line.partition(" ")
            if key == "BITMAP":
                break
            attributes[key] = value
        code = int(attributes["ENCODING"])
        box = tuple(map(int, attributes["BBX"].split()))
        bitmap_start = lines.index("BITMAP") + 1
        rows = lines[bitmap_start:lines.index("ENDCHAR")]
        if len(rows) != box[1] or code in glyphs:
            raise ValueError(f"Malformed/duplicate BDF character U+{code:04X}")
        glyphs[code] = {"box": box, "rows": rows,
                        "advance": int(attributes["DWIDTH"].split()[0])}
    return glyphs


def hgr_rows(glyphs, character):
    code = ord(character)
    if code not in glyphs:
        raise ValueError(f"Missing GalmuriMono7 glyph U+{code:04X} ({character})")
    glyph = glyphs[code]
    width, height, x, y = glyph["box"]
    output = bytearray(8)
    stride_bits = ((width + 7) // 8) * 8
    for row, raw in enumerate(glyph["rows"]):
        bits = int(raw, 16)
        target_y = 7 - (y + height) + row
        for col in range(width):
            if bits & (1 << (stride_bits - 1 - col)):
                target_x = x + col
                if not 0 <= target_x < 7 or not 0 <= target_y < 8:
                    raise ValueError(f"Glyph does not fit losslessly in 7x8: U+{code:04X}")
                output[target_y] |= 1 << target_x
    return bytes(output)
