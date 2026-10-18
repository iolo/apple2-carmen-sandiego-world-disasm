"""Verify the saved case on disposable ProDOS media and optional fresh restore."""

import argparse
from pathlib import Path
import subprocess

from .common import DOCS, ROOT, original_inputs, read_json, sha256, write_json


def extract(image, name):
    return subprocess.run(["a2kit", "get", "-d", str(image), "-f", name, "-t", "raw", "--trunc"],
                          capture_output=True, check=True).stdout


def verify(image, checkpoint, name, restored=None, restored_image=None):
    original_inputs()
    before = read_json(checkpoint)["case_state"]
    roster = extract(image, "F")
    slots = [slot for slot in range(13) if roster[slot*19:slot*19+16].rstrip(b"\xff") == name.encode("ascii")]
    if len(slots) != 1:
        raise ValueError(f"Expected exactly one detective {name}, got slots {slots}")
    slot = slots[0]
    if roster[slot*19+18] != 1:
        raise ValueError("Saved-case roster flag is not set on disk")
    cases = extract(image, "H")
    page = cases[slot*256:(slot+1)*256]
    if page[:33] != bytes(before) or page[33:] != bytes(223):
        raise ValueError("H saved page does not contain the captured case and zero padding")
    modified = []
    files = read_json(ROOT / "reconstruction/manifest.json")["images"]["po"]["files"]
    for module, record in files.items():
        if sha256(extract(image, module)) != record["sha256"]:
            modified.append(module)
    if sorted(modified) != ["F", "H"]:
        raise ValueError(f"Save changed files other than F/H: {modified}")
    report = {"format": 1, "saved_image": str(image), "saved_image_sha256": sha256(image.read_bytes()),
              "detective": name, "slot": slot, "case_state": before, "resume_flag": 1,
              "modified_files": modified, "saved_case_and_padding_match": True,
              "fresh_process_restore": None}
    if restored:
        after = read_json(restored)["case_state"]
        expected = before.copy()
        expected[26] = 2
        if after != expected:
            raise ValueError(f"Fresh restore differs from expected state: {list(enumerate(zip(expected, after)))}")
        if not restored_image:
            raise ValueError("Provide the independently booted image for the restored flag check")
        new_roster = extract(restored_image, "F")
        if new_roster[slot*19+18] != 0:
            raise ValueError("Restore did not clear the F resume flag on disk")
        report["fresh_process_restore"] = {"checkpoint": str(restored), "case_state": after,
            "restored_image": str(restored_image), "restored_image_sha256": sha256(restored_image.read_bytes()),
            "expected_change": "N_RESTORE_SAVED_CASE sets byte $1A (menu selection) to 2",
            "changed_case_offsets": [i for i,(a,b) in enumerate(zip(before,after)) if a != b],
            "resume_flag_after_restore": 0}
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--restored", type=Path)
    parser.add_argument("--restored-image", type=Path)
    args = parser.parse_args()
    report = verify(args.image, args.before, args.name, args.restored, args.restored_image)
    write_json(DOCS / "runtime/mame-save-restore.json", report)
    print("Saved case matches on disk; only F/H changed." +
          (" Fresh-process restore matches; resume flag cleared." if args.restored else " Fresh restore pending."))


if __name__ == "__main__":
    main()
