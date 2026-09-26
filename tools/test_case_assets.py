"""Verify case-field interpretation against captured runtime and disk state."""

import json
from pathlib import Path
import unittest

from extract_assets import (c_name_tables, c_clue_labels, case_snapshot_view,
                            h_case_views, score_records, null_strings)
from case_state import decode_snapshot, encode_snapshot


ROOT = Path(__file__).resolve().parents[1]


class CaseAssetTests(unittest.TestCase):
    def test_editing_clock_preserves_every_other_snapshot_byte(self):
        record = json.loads((ROOT / "docs/runtime/po-boot.json").read_text())
        raw = bytes(record["case_memory"]["bytes"])
        state = decode_snapshot(raw)
        self.assertEqual(encode_snapshot(state), raw)
        state["hour"] = 20
        edited = encode_snapshot(state)
        self.assertEqual([i for i, (a, b) in enumerate(zip(raw, edited)) if a != b], [0x13])
        self.assertEqual(edited[0x13], 20)

    def test_missing_route_slot_is_rejected(self):
        state = decode_snapshot(bytes(33))
        state["route_slots"].pop()
        with self.assertRaisesRegex(ValueError, "route_slots needs 13"):
            encode_snapshot(state)

    def names_and_clues(self, variant):
        data = (ROOT / "assets" / variant / "C.bin").read_bytes()
        treasures = null_strings((ROOT / "assets" / variant / "I.bin").read_bytes())
        return c_name_tables(data), c_clue_labels(data), [row["text"] for row in treasures]

    def test_captured_runtime_distinguishes_origin_and_hideout(self):
        record = json.loads((ROOT / "docs/runtime/po-boot.json").read_text())
        names, clues, treasures = self.names_and_clues("po")
        view = case_snapshot_view(bytes(record["case_memory"]["bytes"]), names, clues, treasures)
        self.assertEqual(view["starting_city"]["name"], "Paris")
        self.assertEqual(view["hideout_city"]["name"], "Budapest")
        self.assertEqual(view["current_city"]["name"], "Paris")
        self.assertEqual(view["clock"], {"day": {"value": 6, "name": "Sun"}, "hour": 13})
        self.assertEqual(view["city_investigation_count"], 1)
        self.assertEqual(view["city_menu_selection"]["label"], "Investigate")
        self.assertEqual(view["treasure"]["text"], "the elevator from the Eiffel Tower")

    def test_empty_roster_slots_do_not_have_a_resume_flag(self):
        for variant in ("disk1", "po"):
            base = ROOT / "assets" / variant
            names, clues, treasures = self.names_and_clues(variant)
            roster = score_records((base / "F.bin").read_bytes())
            view = h_case_views((base / "H.bin").read_bytes(), roster, names, clues, treasures)
            self.assertEqual(len(view["slots"]), 13)
            for slot, detective in zip(view["slots"], roster["slots"]):
                if detective["empty"]:
                    self.assertFalse(slot["resume_flag_set"])
                if slot["unused_page"]:
                    self.assertIsNone(slot["snapshot"])


if __name__ == "__main__":
    unittest.main()
