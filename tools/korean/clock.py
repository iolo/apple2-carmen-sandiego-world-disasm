"""Compile the two clock word bitmaps and preserve the original D glyph ABI."""

from copy import deepcopy
import sys

from .common import ROOT, read_json, sha256
from .font import hgr_rows, load_bdf

sys.path.insert(0, str(ROOT / "tools"))
from d_font import encode_d


def compile_clock(encoding, entries, *, synthetic=True):
    original = read_json(ROOT / "assets/decoded/po/D-font.json")
    if encode_d(original) != (ROOT / "assets/po/D.bin").read_bytes():
        raise ValueError("Original editable D font no longer reproduces the verified English asset")
    changed = deepcopy(original)
    glyphs = load_bdf()
    replacements = []
    for identifier, code in (("bitmap.d.am", 0x85), ("bitmap.d.pm", 0x86)):
        text = entries[identifier]["translation"]
        if synthetic:
            text = encoding.synthetic(text)
        if len(text) != 2 or any(character not in encoding.ids for character in text):
            raise ValueError("Clock words must be two assigned Hangul cells; recheck layout for any change")
        cells = [hgr_rows(glyphs, character) for character in text]
        rows = []
        for y in range(8):
            pixels = [bool(cells[0][y] & (1 << x)) for x in range(7)] + [False]
            pixels += [bool(cells[1][y] & (1 << x)) for x in range(7)]
            # D stores seven useful HGR bits plus a phase bit per byte.
            packed = [sum(1 << bit for bit in range(7) if start+bit < 15 and pixels[start+bit])
                      for start in (0, 7, 14)]
            rows.append("".join("#" if byte & (1 << bit) else "." for byte in packed for bit in range(8)))
        record = changed["glyphs"][code-0x20]
        record.update(width_byte=15, height=8, rows=rows)
        replacements.append({"id": identifier, "character_code": code, "glyph_index": code-0x20,
                             ("synthetic_text" if synthetic else "approved_text"): text,
                             "width": 15, "height": 8, "rows": rows})
    for old, new in zip(original["glyphs"], changed["glyphs"]):
        if old["code"] not in (0x85, 0x86) and old != new:
            raise ValueError("Clock generation changed an unrelated D glyph")
    data = encode_d(changed)
    if len(data) > 1536:
        raise ValueError(f"STOP: D requires {len(data)} bytes; 1536 available; shortfall {len(data)-1536}")
    return data, {"original_bytes": len(encode_d(original)), "bytes": len(data), "sha256": sha256(data),
                  "glyph_count_unchanged": len(changed["glyphs"]), "replacements": replacements,
                  "layout": {"weekday": {"left": 106, "top": 9, "width": 7, "height": 8},
                             "meridiem": {"left": 116, "top": 9, "width": 15, "height": 8},
                             "hour_digits": {"left": 113, "top": 21, "max_width": 15, "height": 7},
                             "interior_horizontal_bounds": [106,132]}}


def patch_source(source, replace_once):
    start, end = source.index("N_DRAW_CLOCK_WEEKDAY:"), source.index("N_DRAW_COMMON_SCREEN_BACKGROUND:")
    clock = source[start:end]
    # Two rows stay inside the original clock: weekday at left + full 오전/오후
    # at right, followed by the unchanged Arabic hour digits centered below.
    for old, new in (("lda     #$3C", "lda     #$37"),
                     ("lda     #$10\n        sta     $98", "lda     #$11\n        sta     $98"),
                     ("ldx     #$35\n        ldy     #$42", "ldx     #$35\n        ldy     #$39"),
                     ("ldx     #$35\n        ldy     #$3D", "ldx     #$35\n        ldy     #$42"),
                     ("lda     #$0F\n        sta     $70", "lda     #$10\n        sta     $70"),
                     ("lda     #$03\n        sta     $71", "lda     #$01\n        sta     $71"),
                     ("lda     #$18", "lda     #$09"),
                     ("lda     #$1B\n        sta     $98\n        ldx     #$3D", "lda     #$11\n        sta     $98\n        ldx     #$3A"),
                     ("ldy     #$3E", "ldy     #$3A")):
        clock = replace_once(clock, old, new)
    return source[:start] + clock + source[end:]
