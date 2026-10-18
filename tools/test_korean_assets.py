"""Protect source identity, catalog scope and lossless Hangul bitmap extraction."""

from copy import deepcopy
import unittest

from korean.catalog import CATALOG, generate, roundtrip
from korean.clock import compile_clock
from korean.common import ROOT, read_json
from korean.draft import apply, audit
from korean.encoding import GameEncoding, TRAILS
from korean.font import hgr_rows, load_bdf
from korean.measure_draft import wrap
from korean.message_layouts import native_typewriter_layout
from d_font import decode_d


class KoreanAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = generate()

    def target_entries(self):
        return [e for e in self.catalog["entries"]
                if any(r["variant"] == "po" for r in e["references"])]

    def test_english_spans_and_editable_bitmaps_reproduce_original_files(self):
        report = roundtrip(self.catalog)
        self.assertEqual(len(report["files"]), 26)
        target = self.target_entries()
        self.assertEqual(sum(e["id"].startswith("s2.") and bool(e["original"]) for e in target), 920)
        self.assertEqual(sum(e["id"].startswith("c.ui.") for e in target), 130)
        self.assertTrue(any(e["id"] == "bitmap.o.hobby" for e in target))
        self.assertTrue(any(e["id"] == "bitmap.p.jail" for e in target))

    def test_a_missing_or_duplicate_entry_fails_coverage(self):
        missing = deepcopy(self.catalog)
        missing["entries"].pop()
        with self.assertRaisesRegex(ValueError, "count differs"):
            roundtrip(missing)
        duplicate = deepcopy(self.catalog)
        duplicate["entries"][-1] = deepcopy(duplicate["entries"][0])
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            roundtrip(duplicate)

    def test_original_text_cannot_drift_when_draft_translation_changes(self):
        changed = deepcopy(self.catalog)
        item = next(e for e in changed["entries"] if e["id"] == "c.ui.019")
        item["translation"] = "탐정 이름을 영문으로 입력하세요."
        item["status"] = "draft"
        roundtrip(changed)  # Draft work cannot change English reconstruction.
        item["original"] += "!"
        with self.assertRaisesRegex(ValueError, "Original catalog field changed"):
            roundtrip(changed)

    def test_text_mode_and_literal_hash_are_distinct_from_pronouns(self):
        target = self.target_entries()
        text = [e for e in target if any(r["output_mode"] == "TEXT" for r in e["references"])]
        self.assertEqual(len(text), 12)
        self.assertTrue(all(e["status"] == "excluded" and not e["translatable"] for e in text))
        cases = next(e for e in target if e["id"] == "c.ui.018")
        self.assertEqual(cases["original"], "# Cases")
        self.assertEqual(cases["protected_tokens"], [])
        self.assertTrue(any(p["token"] == "@" for e in target if e["id"].startswith("s2.")
                            for p in e["protected_tokens"]))

    def test_service_he_does_not_alias_the_suffix_of_she(self):
        entries = {e["id"]: e for e in self.target_entries()}
        she = entries["c.service.she"]["references"][0]
        he = entries["c.service.he"]["references"][0]
        self.assertEqual(she["offset"] + 4, he["offset"])

    def test_display_name_translation_cannot_remove_english_input_guards(self):
        entries = self.target_entries()
        guarded = [e for e in entries if e.get("input_uses")]
        self.assertEqual(len(guarded), 15)  # Ten suspects and the first five ranks.
        changed = deepcopy(self.catalog)
        next(e for e in changed["entries"] if e["id"] == "c.suspects.00")["input_uses"] = []
        with self.assertRaisesRegex(ValueError, "Original catalog field changed"):
            roundtrip(changed)

    def test_pronoun_consumption_and_inline_suffix_are_part_of_source_contract(self):
        entries = {e["id"]: e for e in self.catalog["entries"]}
        self.assertEqual(entries["n.plural_suffix"]["codec"], "ascii-byte")
        self.assertTrue(all(r["original_hex"] == "73" and r["length"] == 1
                            for r in entries["n.plural_suffix"]["references"]))
        changed = deepcopy(self.catalog)
        next(e for e in changed["entries"] if e["id"] == "k.008")["pronoun_substitution"] = False
        with self.assertRaisesRegex(ValueError, "Original catalog field changed"):
            roundtrip(changed)

    def test_bdf_conversion_preserves_real_pixels_and_rejects_clipping(self):
        glyphs = load_bdf()
        # The pinned BDF's top row for 한 is $44 (MSB-first); HGR is LSB-first.
        self.assertEqual(hgr_rows(glyphs, "한"), bytes([0x22,0x3F,0x69,0x26,0x20,0x02,0x3E,0]))
        self.assertEqual(hgr_rows(glyphs, " "), bytes(8))
        with self.assertRaisesRegex(ValueError, "Missing"):
            hgr_rows({}, "한")
        with self.assertRaisesRegex(ValueError, "fit losslessly"):
            hgr_rows({ord("X"): {"box": (8,1,0,0), "rows": ["01"]}}, "X")

    def test_editing_normalizes_nfc_and_invalidates_the_entire_old_approval(self):
        changed = deepcopy(self.catalog)
        entries = {e["id"]: e for e in changed["entries"]}
        changed["approval"] = {"obsolete": "approval cannot survive an edit"}
        for identifier in ("c.ui.019", "c.ui.020"):
            entries[identifier].update(translation="옛 번역", status="approved")
        self.assertEqual(apply(changed, {"c.ui.019": "한글"}), ["c.ui.019"])
        self.assertEqual(entries["c.ui.019"]["translation"], "한글")
        self.assertIsNone(changed["approval"])
        self.assertEqual(entries["c.ui.020"]["status"], "draft")

    def test_draft_cannot_drop_input_hints_controls_or_embedded_pronouns(self):
        for identifier, invalid, reason in (
                ("c.ui.021", "계속하세요", "input hint"),
                ("c.ui.032", "임무", "renderer controls"),
                ("s2.city00.line03", "돈을 바꿨다", "pronoun markers")):
            with self.subTest(identifier=identifier):
                changed = deepcopy(self.catalog)
                apply(changed, {identifier: invalid})
                with self.assertRaisesRegex(ValueError, reason):
                    audit(changed, persist=False)

    def test_invisible_and_malformed_controls_cannot_enter_review(self):
        for invalid, reason in (("한\u200b글", "literal control"),
                                ("한\x00글", "literal control"),
                                ("<CTRL:GG>한글", "malformed renderer")):
            with self.subTest(invalid=repr(invalid)):
                changed = deepcopy(self.catalog)
                apply(changed, {"c.ui.019": invalid})
                with self.assertRaisesRegex(ValueError, reason):
                    audit(changed, persist=False)

    def test_multibyte_ids_cross_256_without_scanner_delimiter_collisions(self):
        encoding = GameEncoding(chr(0xAC00 + i) for i in range(710))
        text = 'A "#@^ ' + "".join(encoding.characters) + "<CTRL:8D>Z"
        self.assertEqual(encoding.decode(encoding.encode(text)), text)
        for character in encoding.characters:
            pair = encoding.encode(character)
            self.assertEqual(len(pair), 2)
            self.assertTrue(0x90 <= pair[0] <= 0xFE)
            self.assertIn(pair[1], TRAILS)
            self.assertFalse(set(pair) & {0, 0xFF, 0x20, 0x22, 0x23, 0x40, 0x5E})
        for malformed in (b"\x90", b"\x90\x00", b"\x90\x22", b"\xFE\x21", b"\x7F", b"\xFF"):
            with self.subTest(malformed=malformed), self.assertRaises(ValueError):
                encoding.decode(malformed)

    def test_synthetic_glyph_permutation_retains_all_metrics_and_controls(self):
        encoding = GameEncoding("가나다")
        text = '가# 나@ 다^<CTRL:8D>'
        synthetic = encoding.synthetic(text)
        self.assertNotEqual(text, synthetic)
        self.assertEqual(set(c for c in synthetic if ord(c) > 127), set("가나다"))
        self.assertEqual(len(encoding.encode(text)), len(encoding.encode(synthetic)))
        self.assertEqual(encoding.encode(text)[-1], 0x8D)
        with self.assertRaisesRegex(ValueError, "Unencodable"):
            encoding.encode("라")
        with self.assertRaisesRegex(ValueError, "NFC"):
            encoding.encode("가")

    def test_clock_words_preserve_native_font_abi_and_exact_two_cell_pixels(self):
        catalog = read_json(CATALOG)
        entries = {entry["id"]: entry for entry in catalog["entries"]}
        encoding = GameEncoding.from_catalog(catalog)
        data, report = compile_clock(encoding, entries)
        self.assertEqual(len(data), 1507)
        self.assertLessEqual(len(data), 1536)
        old = decode_d((ROOT / "assets/po/D.bin").read_bytes())["glyphs"]
        new = decode_d(data)["glyphs"]
        self.assertEqual(len(new), 107)
        glyphs = load_bdf()
        for before, after in zip(old, new):
            if before["code"] not in (0x85,0x86):
                self.assertEqual(before, after)
        for record in report["replacements"]:
            code = record["character_code"]
            pointer = data[code-32]+256*data[code-32+112]-0xB900
            self.assertEqual(data[pointer:pointer+2], bytes((15,8)))
            cells = [hgr_rows(glyphs, character) for character in record["synthetic_text"]]
            for y in range(8):
                for x in range(15):
                    actual = (data[pointer+2+y*3+x//7] >> (x%7)) & 1
                    expected = 0 if x == 7 else (cells[x//8][y] >> (x%8)) & 1
                    self.assertEqual(actual, expected)

    def test_wide_name_wrap_is_bounded_and_never_loses_a_character(self):
        # This deliberately oversized synthetic word exceeds the report column.
        # Actual name input also has the original variable-pixel-width limit.
        # Native fallback must retain every glyph without scanning before it.
        layout = wrap("W" * 15, {ord("W"): 9}, 24, 24, 126)
        self.assertEqual(layout["lines"], ["W" * 11, "W" * 4])
        self.assertEqual(layout["hard_breaks"], [11])

    def test_typewriter_terminal_nul_keeps_the_native_final_scroll(self):
        widths={32:3,65:7,0x80:8}
        self.assertEqual(native_typewriter_layout('',widths)['lines'],[''])
        for value in ('A<CTRL:8D>','A<CTRL:8D>  ','A<CTRL:8D><CTRL:80>'):
            self.assertEqual(native_typewriter_layout(value,widths)['lines'],['A',''])
        self.assertEqual(native_typewriter_layout('A',widths)['first_text_final_row'],143)

    def test_typewriter_marker_preserves_indentation_after_it(self):
        widths = {ord(c): 7 for c in "x A"}
        widths[128] = 7
        result = wrap("x<CTRL:8D> <CTRL:80>  A", widths, 0, 0, 100,
                      skip_line_marker_80=True)
        self.assertEqual(result["lines"], ["x", "  A"])


if __name__ == "__main__":
    unittest.main()
