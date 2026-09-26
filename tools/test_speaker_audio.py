"""Check the sound player against its independently known counter behavior."""

from pathlib import Path
import unittest

from n_sounds import SOUND_TABLE_ADDRESS
from speaker_audio import SpeakerPlayer


ROOT = Path(__file__).resolve().parents[1]


class SpeakerAudioTests(unittest.TestCase):
    def player(self, module, variant, note, duration=1):
        data = bytearray((ROOT / "assets" / variant / f"{module}.bin").read_bytes())
        table = SOUND_TABLE_ADDRESS[variant] if module == "N" else 0x62CB
        pointer_offset = table - 0x6000 + 33
        track = int.from_bytes(data[pointer_offset:pointer_offset + 2], "little")
        offset = track - 0x6000
        data[offset:offset + 3] = bytes((0x80 | duration, note, 0xFF))
        return SpeakerPlayer(data, table - 0x7E, 0)

    def test_one_duration_unit_runs_256_counter_ticks(self):
        # Period-table entry 1 is 26. The two counters expire every 26 and
        # 25 ticks. Neither can expire together before tick 650, so one
        # duration unit (256 ticks) must produce 9 + 10 accesses.
        for variant in ("disk1", "po"):
            for module in ("N", "R"):
                with self.subTest(variant=variant, module=module):
                    cycles, toggles = self.player(module, variant, 1).run()
                    self.assertEqual(len(toggles), 19)
                    self.assertEqual(toggles, sorted(set(toggles)))
                    self.assertGreater(cycles, toggles[-1])

    def test_rest_redirects_accesses_away_from_speaker(self):
        for module in ("N", "R"):
            cycles, toggles = self.player(module, "disk1", 0).run()
            self.assertGreater(cycles, 0)
            self.assertEqual(toggles, [])

    def test_disabled_sound_returns_without_consuming_track(self):
        player = self.player("N", "disk1", 1)
        player.memory[0x18] = 0
        self.assertEqual(player.run(), (12, []))


if __name__ == "__main__":
    unittest.main()
