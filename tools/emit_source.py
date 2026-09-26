#!/usr/bin/env python3
"""Create an initial ca65 disassembly for candidate executable files.

The generated labels are mechanical. A round-trip check proves byte identity,
not that every instruction boundary or data table has been understood.
"""

import json
import argparse
from pathlib import Path
import subprocess
import tempfile

from reconstruct import CODE_FILES, MANIFEST, ROOT, assemble, digest, source_path


def emit(variant, name, record, force=False):
    target = source_path(variant, name)
    if target.exists() and not force:
        print(f"{target.relative_to(ROOT)}: kept existing source")
        return
    asset = ROOT / record["asset"]
    raw = asset.read_bytes()
    if digest(raw) != record["sha256"]:
        raise RuntimeError(f"{asset}: hash differs from manifest")
    addr = int.from_bytes(bytes.fromhex(record["file_image"]["aux"]), "little")
    with tempfile.TemporaryDirectory(prefix="carmen-disasm-") as temp:
        output = Path(temp) / "listing.s"
        proc = subprocess.run(["da65", "-S", hex(addr), "-o", str(output), str(asset)],
                              capture_output=True, text=True)
        if proc.returncode:
            raise RuntimeError(proc.stderr)
        lines = output.read_text().splitlines()
    first = next(i for i, line in enumerate(lines) if '.setcpu "6502"' in line)
    header = [
        f"; {variant}/{name}: ${addr:04X}, {len(raw)} bytes, sha256 {record['sha256']}",
        "; Initial mechanical disassembly; instruction boundaries and tables need review.",
        "; This file is verified to assemble to exactly the source file bytes.",
        '.segment "CODE"',
        "",
    ]
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(header + lines[first:]) + "\n")
    rebuilt = assemble(variant, name, addr)
    if rebuilt != raw:
        target.unlink()
        raise RuntimeError(f"{variant}/{name}: disassembly failed byte-for-byte round trip")
    print(f"{target.relative_to(ROOT)}: {len(raw)} bytes round-tripped")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="overwrite existing listings")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    for variant in ("disk1", "po"):
        for name, record in manifest["images"][variant]["files"].items():
            if name in CODE_FILES:
                emit(variant, name, record, force=args.force)


if __name__ == "__main__":
    main()
