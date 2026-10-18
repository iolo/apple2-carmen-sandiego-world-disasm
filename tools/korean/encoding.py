"""Deterministic Korean game encoding and unpatched draft/synthetic fixtures.

These files are compiler inputs for capacity experiments, never game media.
ASCII and native controls keep their values. Non-ASCII glyphs use two bytes
that cannot contain native terminators, spaces, quotes or pronoun markers.
"""

import re
import unicodedata

from .catalog import CATALOG, CONTROL_RE
from .common import BUILD, DOCS, original_inputs, read_json, sha256, write_json
from .draft import audit
from .font import hgr_rows, load_bdf


TRAILS = tuple(b for b in range(0x21, 0x7F) if b not in (0x22, 0x23, 0x40, 0x5E))
LEAD_FIRST, LEAD_LAST = 0x90, 0xFE
MAX_GLYPHS = len(TRAILS) * (LEAD_LAST - LEAD_FIRST + 1)


class GameEncoding:
    def __init__(self, characters):
        self.characters = tuple(sorted(set(characters)))
        if any(len(c) != 1 or ord(c) < 0xA0 or unicodedata.category(c) in ("Cc", "Cf")
               for c in self.characters):
            raise ValueError("Glyph table must contain visible non-ASCII characters only")
        if len(self.characters) > MAX_GLYPHS:
            raise ValueError("Character set exceeds two-byte encoding capacity")
        self.ids = {c: i for i, c in enumerate(self.characters)}
        self.trail_ids = {b: i for i, b in enumerate(TRAILS)}

    @classmethod
    def from_catalog(cls, catalog):
        return cls(c for e in catalog["entries"] if e["translatable"]
                   and e["translation"] is not None for c in e["translation"] if ord(c) > 127)

    def encode(self, text):
        if unicodedata.normalize("NFC", text) != text:
            raise ValueError("Text must be NFC before encoding")
        output = bytearray()
        position = 0
        while position < len(text):
            control = CONTROL_RE.match(text, position)
            if control:
                value = int(control[1], 16)
                if not 0x80 <= value <= 0x8F:
                    raise ValueError("Control byte is outside the reserved range")
                output.append(value)
                position = control.end()
                continue
            if re.match(r"<ctrl", text[position:], re.IGNORECASE):
                raise ValueError("Malformed renderer control notation")
            character = text[position]
            value = ord(character)
            if 0x20 <= value <= 0x7E:
                output.append(value)
            elif character in self.ids:
                identifier = self.ids[character]
                output.extend((LEAD_FIRST + identifier // len(TRAILS), TRAILS[identifier % len(TRAILS)]))
            else:
                raise ValueError(f"Unencodable character U+{value:04X}")
            position += 1
        return bytes(output)

    def decode(self, data):
        """Decode a payload without its NUL; reject every malformed byte pair."""
        output, position = [], 0
        while position < len(data):
            value = data[position]
            if 0x20 <= value <= 0x7E:
                output.append(chr(value))
            elif 0x80 <= value <= 0x8F:
                output.append(f"<CTRL:{value:02X}>")
            elif LEAD_FIRST <= value <= LEAD_LAST:
                if position + 1 == len(data):
                    raise ValueError("Truncated multibyte glyph")
                trail = data[position + 1]
                if trail not in self.trail_ids:
                    raise ValueError(f"Reserved/invalid glyph trail ${trail:02X}")
                identifier = (value - LEAD_FIRST) * len(TRAILS) + self.trail_ids[trail]
                if identifier >= len(self.characters):
                    raise ValueError("Unassigned glyph ID")
                output.append(self.characters[identifier])
                position += 1
            else:
                raise ValueError(f"Invalid payload byte ${value:02X}")
            position += 1
        return "".join(output)

    def synthetic(self, text):
        """A bijective substitution: identical charset, metrics, bytes and controls."""
        if not self.characters:
            return text
        rotated = {c: self.characters[(i + 1) % len(self.characters)]
                   for i, c in enumerate(self.characters)}
        return "".join(rotated.get(c, c) for c in text)

    def entry(self, entry, synthetic=False):
        text = entry["translation"]
        if text is None:
            if entry["translatable"] or entry["original"]:
                raise ValueError(f"Missing/excluded nonempty draft: {entry['id']}")
            text = ""  # Structural S2 NULs are retained, never invented text.
        if synthetic:
            text = self.synthetic(text)
        if entry["codec"] == "bitmap":
            text = text.replace("\n", "<CTRL:8D>")
        payload = self.encode(text)
        if self.decode(payload) != text:
            raise ValueError(f"Encoding round trip failed: {entry['id']}")
        if entry["codec"] == "ascii-byte":
            # N's English plural append will be removed as an instruction span.
            if payload:
                raise ValueError("Korean inline plural must be empty")
            return payload
        return payload + b"\0"

    def manifest(self):
        return {"format": 1, "encoding": "carmen-ko-2byte-v1", "ascii": [0x20, 0x7E],
                "controls": [0x80, 0x8F], "lead_range": [LEAD_FIRST, LEAD_LAST],
                "trails": list(TRAILS), "terminators": [0, 255],
                "reserved_internal": [0x7F], "glyph_bytes": 8,
                "glyphs": [{"id": i, "character": c, "unicode": f"U+{ord(c):04X}",
                            "encoded_hex": self.encode(c).hex(), "font_offset": i * 8}
                           for i, c in enumerate(self.characters)]}


def compile_fixtures():
    catalog = read_json(CATALOG)
    coverage = audit(catalog, complete=True)
    identity = original_inputs()
    encoding = GameEncoding.from_catalog(catalog)
    glyphs = load_bdf()
    font = b"".join(hgr_rows(glyphs, c) for c in encoding.characters)
    directory = BUILD / "draft-fixtures"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "KF.bin").write_bytes(font)
    write_json(directory / "encoding.json", encoding.manifest())
    fixtures = []
    for entry in catalog["entries"]:
        if not entry["translatable"]:
            continue
        draft = encoding.entry(entry)
        synthetic = encoding.entry(entry, synthetic=True)
        if len(draft) != len(synthetic):
            raise ValueError(f"Synthetic size mismatch: {entry['id']}")
        fixtures.append({"id": entry["id"], "bytes": len(draft),
                         "draft_hex": draft.hex(), "synthetic_hex": synthetic.hex()})
    # The complete substitution must retain every cell, including caption-only cells.
    visible = "".join(e["translation"] for e in catalog["entries"] if e["translatable"])
    if {c for c in encoding.synthetic(visible) if ord(c) > 127} != set(encoding.characters):
        raise ValueError("Synthetic fixtures did not preserve the complete charset")
    write_json(directory / "strings.json", {"catalog_sha256": coverage["catalog_sha256"],
                                            "status": "unapproved; no game image patched",
                                            "entries": fixtures})
    report = {"format": 1, "catalog_sha256": coverage["catalog_sha256"],
              "original_inputs": identity, "strings_roundtripped": len(fixtures),
              "non_ascii_glyphs": len(encoding.characters),
              "hangul_syllables": coverage["unique_hangul_syllables"],
              "font_bytes": len(font), "font_sha256": sha256(font),
              "synthetic": "bijective rotation of non-ASCII glyphs; same charset, metrics, encoded lengths and controls",
              "directory": str(directory.relative_to(BUILD.parent.parent)),
              "status": "compiler fixtures only; native evidence and remaining integration gates recorded separately under docs/korean/runtime"}
    write_json(DOCS / "encoding-roundtrip.json", report)
    return report


def main():
    report = compile_fixtures()
    print(f"Round-tripped {report['strings_roundtripped']} drafts; "
          f"{report['non_ascii_glyphs']} glyphs, {report['font_bytes']} font bytes; no game image patched")


if __name__ == "__main__":
    main()
