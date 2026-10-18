"""Synthetic complete-charset native copy/expansion fixtures, including pages."""

from . import test_mode
from .catalog import CATALOG
from .common import BUILD, ROOT, read_json, sha256, write_json
from .encoding import GameEncoding
from .game_text import assert_bound
from .library import assemble


def build(mode="synthetic"):
    directory = test_mode.directory(mode) / "reader-probe"
    directory.mkdir(parents=True, exist_ok=True)
    catalog = read_json(CATALOG)
    encoding = GameEncoding.from_catalog(catalog)
    entries = {e["id"]: e for e in catalog["entries"]}
    n = read_json(BUILD / "maps/N-symbols.json")
    c = read_json(test_mode.directory(mode) / "text/C-source/C-symbols.json")
    all_glyphs = "".join(encoding.characters)
    cases = []
    for female in (False, True):
        for reader in ("N", "C"):
            # $80/$81/$8D must remain literal native controls. Every assigned
            # lead/trail pair must survive; none may become a dictionary word.
            text = (("#/@/^ " if reader == "N" else "# # ") + all_glyphs + "<CTRL:80><CTRL:81><CTRL:8D>" + encoding.characters[-1])
            replacements = ({"#": entries[f"c.ui.{68 if female else 67:03}"]["translation"],
                             "@": entries[f"c.ui.{104 if female else 103:03}"]["translation"],
                             "^": entries["c.ui.105"]["translation"]} if reader == "N" else
                            {"#": entries[f"c.service.{'she' if female else 'he'}"]["translation"]})
            expanded = "".join(replacements.get(ch, ch) for ch in text)
            cases.append((f"{reader}-{'female' if female else 'male'}-all", reader, female, 254, text, expanded))
    for text, prefix, label in (("A", 254, "period-at-ff"), ('"', 255, "quote-at-ff"),
                                (encoding.characters[-1], 254, "glyph-at-ff")):
        cases.append(("N-"+label, "N", False, prefix, text, text))
    probes = []
    for name, reader, female, prefix, text, expanded in cases:
        # Even the test's pronoun strings use the same bijection as the disk.
        raw = encoding.encode(test_mode.text(text, encoding, mode)) + b"\0"
        result = encoding.encode(test_mode.text(expanded, encoding, mode))
        expected = b"P"*prefix + result + (b"" if result.endswith(b'"') else b".") + b"\0"
        assert_bound("Native reader output", len(expected), 1792)
        # The K scanner skips two complete strings, including a source-page
        # boundary. This input is borrowed only during the disposable RAM test.
        source = raw if reader == "N" else b"Z"*254+b"\0\0"+raw
        address = 0x0EFD if reader == "N" else 0x5000
        pointer = address + len(source)-1
        code = '.setcpu "6502"\n.segment "CODE"\nPROBE_ENTRY:\n        sei\n        cld\n'
        code += ("        lda #$00\n        sta $DA\n        lda #$A0\n        sta $DB\n"
                 f"        lda #${prefix:02X}\n        sta $AC\n        lda #${0 if female else 9:02X}\n        sta $00\n")
        if reader == "N":
            code += (f"        lda #${address & 255:02X}\n        sta $C4\n        lda #${address >> 8:02X}\n        sta $C5\n"
                     f"        jsr ${n['N_EXPAND_TOKENIZED_TEXT']:04X}\n")
        else:
            code += "        ldx #$02\n        jsr $D215\n"
        code += f"        jsr ${n['N_END_TEXT_SENTENCE']:04X}\nPROBE_DONE: jmp PROBE_DONE\n"
        (directory / f"{name}.s").write_text(code)
        binary, symbols = assemble(directory / f"{name}.s", directory, name, 0x0800, 0x400)
        (directory / f"{name}-source.bin").write_bytes(source)
        (directory / f"{name}-expected.bin").write_bytes(expected)
        probes.append({"name": name, "mode": reader, "female": female, "prefix": prefix,
                       "source_address": address, "source_pointer_at_nul": pointer,
                       "output_bytes": len(expected), "expected_sha256": sha256(expected),
                       "binary_sha256": sha256(binary), "symbols": symbols})
    report = {"format": 1, "probes": probes, "glyphs_per_all_case": len(encoding.characters),
              "c_service_symbols": {key: c[key] for key in ("C_APPEND_5000_TEXT", "C_COPY_STRING")},
              **test_mode.identity(mode)}
    write_json(directory / "manifest.json", report)
    return report


if __name__ == "__main__":
    build()
