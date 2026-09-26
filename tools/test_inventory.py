"""Ensure directory coverage cannot silently omit a valid source file."""

import unittest

from prodos_inventory import root_inventory
from reconstruct import ROOT, IMAGES, image_inventory, run


class InventoryTests(unittest.TestCase):
    def test_omitted_source_file_fails_coverage(self):
        spec = {**IMAGES["disk1"], "files": IMAGES["disk1"]["files"][:-1]}
        with self.assertRaisesRegex(RuntimeError, r"omitted \['U'\]"):
            image_inventory(ROOT / spec["input"], spec, True)

    def test_declared_count_cannot_hide_a_valid_entry(self):
        image = ROOT / IMAGES["disk1"]["input"]

        def read_block(number):
            data = bytearray(run("a2kit", "get", "-d", str(image), "-f", str(number), "-t", "block"))
            if number == 2:
                data[37:39] = (20).to_bytes(2, "little")
            return data

        with self.assertRaisesRegex(RuntimeError, "declares 20 files but has 21"):
            root_inventory(read_block)


if __name__ == "__main__":
    unittest.main()
