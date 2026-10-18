"""Build a disposable full-size synthetic 800K ProDOS game image.

The CLI always builds synthetic data. The production entry point can reuse
the image assembler only after exact whole-catalog approval verification.
"""

from copy import deepcopy
import json
from pathlib import Path
import sys
import tempfile

from .common import BUILD, DOCS, ROOT, read_json, sha256, write_json
from .game_text import assert_bound, build as build_text, replace_once
from .library import assemble
from .capacity import disk_capacity

sys.path.insert(0, str(ROOT / "tools"))
from reconstruct import IMAGES, content_for, make_fimg, run
from prodos_inventory import root_inventory


def loaders(directory):
    """Keep all eight B public entry addresses; extend internal module tables."""
    directory.mkdir(parents=True, exist_ok=True)
    source = (ROOT / "src/po/B.s").read_text()
    for label, suffix in (("B_MODULE_PATH_LO_TAIL", ", <B_FILE_KL, <B_FILE_KF"),
                           ("B_MODULE_PATH_HI", ", >B_FILE_KL, >B_FILE_KF"),
                           ("B_MODULE_BUFFER_PAGE", ", $92, $60")):
        lines = source.splitlines()
        matches = [i for i, line in enumerate(lines) if line.startswith(label + ":")]
        if len(matches) != 1:
            raise ValueError("Loader module table source contract changed")
        lines[matches[0]] += suffix
        source = "\n".join(lines) + "\n"
    source += "B_FILE_KL: .byte $02, 'k', 'l', $00\nB_FILE_KF: .byte $02, 'k', 'f', $00\n"
    (directory / "B.s").write_text(source)
    bdata, bsymbols = assemble(directory / "B.s", directory, "B", 0x9800, 0x600)
    for i, label in enumerate(("B_LOAD_MODULE", "B_ENTER_INTRO", "B_ENTER_GAME", "B_LOAD_S2_RECORD",
                                "B_LOAD_S2_TEXT", "B_SAVE_F", "B_SAVE_G", "B_SAVE_H")):
        if bsymbols[label] != 0x9800 + i*3:
            raise ValueError("B public entry moved")
    source = (ROOT / "src/po/WORLD.SYSTEM.s").read_text()
    source = replace_once(source, "        jsr     C_COPY_2200_TO_AUX_D400\n        jmp     B_ENTER_INTRO",
        "        jsr     C_COPY_2200_TO_AUX_D400\n"
        "; Install KL/KF after all original auxiliary copies, before R replaces $6000.\n"
        "K_BOOT_LOAD_LIBRARY: ldy #$11\n        jsr B_LOAD_MODULE\n        bcs K_BOOT_LOAD_FAILED\n"
        "        ldy #$12\n        jsr B_LOAD_MODULE\n        bcs K_BOOT_LOAD_FAILED\n"
        "K_BOOT_INSTALL_FONT: jsr $9200\nK_BOOT_FONT_INSTALLED: jmp B_ENTER_INTRO\n"
        "K_BOOT_LOAD_FAILED: jmp BOOT_REPORT_LOAD_ERROR")
    (directory / "WORLD.SYSTEM.s").write_text(source)
    world, symbols = assemble(directory / "WORLD.SYSTEM.s", directory, "WORLD.SYSTEM", 0x2000, 0x2000)
    return {"B": (bdata, bsymbols), "WORLD.SYSTEM": (world, symbols)}


def normalize_dates(path, metadata):
    """a2kit timestamps volume/files on import; restore explicit source dates."""
    image = bytearray(path.read_bytes())
    original = (ROOT / "carmen-world.po").read_bytes()
    # ProDOS volume header entry starts at block 2 + 4; creation date/time
    # is entry + 24 (four bytes). File timestamps are supplied via file images.
    image[2*512+28:2*512+32] = original[2*512+28:2*512+32]
    inventory = root_inventory(lambda block: image[block*512:(block+1)*512])
    for block in inventory["directory_blocks"]:
        for slot in range(1 if block == 2 else 0, 13):
            entry = block*512 + 4 + slot*39
            if image[entry] >> 4 == 0:
                continue
            name = image[entry+1:entry+1+(image[entry] & 15)].decode("ascii")
            fields = metadata[name]["file_image"]
            for field, offset in (("created", 24), ("modified", 33)):
                value = bytes.fromhex(fields[field])
                if len(value) != 4:
                    raise ValueError("ProDOS timestamp must be four bytes")
                image[entry+offset:entry+offset+4] = value
    path.write_bytes(image)


def build(*, approved=False):
    receipt = None
    if approved:
        from .approval import require
        receipt = require()
    text = build_text(approved=approved)
    mode = "approved" if approved else "synthetic"
    directory = BUILD / mode
    source_paths = ["tools/korean/"+name+".py" for name in
                    ("synthetic", "game_text", "clock", "captions", "library", "renderers", "encoding", "font", "draft", "common")]
    source_paths += ["src/korean/"+name+".s" for name in ("library", "render_hooks", "text_hooks", "caption_engine", "caption_hooks")]
    source_paths += ["src/po/"+name+".s" for name in ("N", "B", "WORLD.SYSTEM")]
    source_paths += ["src/disk1/C.s", "assets/decoded/po/D-font.json"]
    if approved:
        source_paths += ["tools/korean/approval.py", "tools/korean/production.py"]
    inputs = {"sources": {name: sha256((ROOT / name).read_bytes()) for name in source_paths},
              "catalog_sha256": text["catalog_sha256"], "original_inputs": text["original_inputs"],
              "library_sha256": text["renderer_library_sha256"],
              "font_sha256": sha256((BUILD / "draft-fixtures/KF.bin").read_bytes()),
              "font_source_sha256": sha256((ROOT / "assets/korean/font/source.json").read_bytes())}
    if receipt is not None:
        inputs["approval_sha256"] = sha256((ROOT / "assets/korean/approval.json").read_bytes())
    previous = read_json(directory / "manifest.json") if (directory / "manifest.json").exists() else None
    loader_files = loaders(directory / "loaders")
    replacements = {name: (ROOT / record["path"]).read_bytes() for name, record in text["files"].items()}
    replacements.update({name: value[0] for name, value in loader_files.items()})
    replacements.update(KF=(BUILD / "draft-fixtures/KF.bin").read_bytes())
    source_manifest = read_json(ROOT / "reconstruction/manifest.json")["images"]["po"]["files"]
    metadata, contents, records = {}, {}, {}
    names = IMAGES["po"]["files"] + ["KL", "KF"]
    for name in names:
        record = deepcopy(source_manifest[name] if name in source_manifest else source_manifest["I"])
        if name not in source_manifest:
            record["file_image"]["aux"] = (0x9200 if name == "KL" else 0x6000).to_bytes(2, "little").hex().upper()
        # Build and verify unchanged English assets through their existing source
        # authorities. Original files and the ordinary English build are untouched.
        data = replacements[name] if name in replacements else content_for("po", name, record)
        if name not in replacements and sha256(data) != record["sha256"]:
            raise ValueError("Unchanged English source no longer reproduces its verified asset: " + name)
        assert_bound(name + " ProDOS EOF", len(data), 0xFFFFFF)
        record["file_image"]["eof"] = len(data).to_bytes(3, "little").hex().upper()
        record["file_image"]["full_path"] = name
        contents[name] = data
        metadata[name] = record
        records[name] = {"bytes": len(data), "sha256": sha256(data),
                         "changed": name in replacements, "metadata": record["file_image"]}
    if approved:
        baseline = read_json(DOCS / "synthetic-build.json")
        reviewed = read_json((ROOT / receipt["review_manifest"]).parent / "readiness.json")
        if baseline["image_sha256"] != reviewed["synthetic_image_sha256"]:
            raise ValueError("Synthetic baseline differs from the reviewed native evidence")
        if baseline["catalog_sha256"] != text["catalog_sha256"] or text["remaining_display_entries"]:
            raise ValueError("Current approved catalog lacks a complete full-size synthetic baseline")
        for name, data in contents.items():
            if len(data) != baseline["files"][name]["bytes"]:
                raise ValueError("Production footprint differs from the measured synthetic baseline: " + name)
        # Verify all excluded TEXT MODE strings in the actual generated files.
        for entry in read_json(ROOT / "assets/korean/catalog.json")["entries"]:
            for ref in entry["references"]:
                if ref["variant"] == "po" and ref["output_mode"] == "TEXT":
                    if entry["translatable"] or bytes.fromhex(ref["original_hex"]) not in contents[ref["file"]]:
                        raise ValueError("TEXT MODE exclusion changed: " + entry["id"])
    target = directory / ("carmen-world-ko.po" if approved else "carmen-world-synthetic.po")
    with tempfile.TemporaryDirectory(prefix="image-", dir=directory) as temporary:
        pending = Path(temporary) / target.name
        run("a2kit", "mkdsk", "-o", "prodos", "-v", "CARMEN.WORLD", "-t", "po",
            "-k", "3.5in-apple-800", "-d", str(pending))
        for name in names:
            run("a2kit", "put", "-d", str(pending), "-f", name, "-t", "any",
                input_bytes=make_fimg(name, metadata[name], contents[name]))
        normalize_dates(pending, metadata)
        image = pending.read_bytes()
        inventory = root_inventory(lambda block: image[block*512:(block+1)*512])
        if set(inventory["files"]) != set(names) or inventory["malformed_unused_entries"]:
            raise ValueError(f"Unexpected {mode} image directory")
        for name in names:
            actual = run("a2kit", "get", "-d", str(pending), "-f", name, "-t", "raw", "--trunc")
            if actual != contents[name]:
                raise ValueError(f"{mode} disk payload mismatch: " + name)
            actual_metadata = json.loads(run("a2kit", "get", "-d", str(pending), "-f", name, "-t", "any"))
            for field in ("fs_type", "aux", "eof", "access", "created", "modified", "version", "min_version"):
                if actual_metadata[field] != metadata[name]["file_image"][field]:
                    raise ValueError(f"{mode} disk metadata mismatch: {name}/{field}")
        repeated = previous is not None and previous.get("build_inputs") == inputs
        if repeated and sha256(image) != previous["image_sha256"]:
            raise ValueError(f"Same {mode} build inputs produced a different disk image")
        if approved:
            from .approval import require
            if require() != receipt:
                raise ValueError("Human approval changed during the build")
        pending.replace(target)
    report = {"format": 1, "mode": mode, "catalog_sha256": text["catalog_sha256"],
              "original_inputs": text["original_inputs"], "image": str(target.relative_to(ROOT)),
              "build_inputs": inputs, "repeated_build_identical": True if repeated else None,
              "image_sha256": sha256(target.read_bytes()), "files": records,
              "disk": disk_capacity(target), "loader_symbols": {name: pair[1] for name, pair in loader_files.items()},
              "covered_entries": text["covered_entries"], "remaining_display_entries": text["remaining_display_entries"],
              "status": ("synthetic image and metadata pass static checks; native evidence is recorded separately under docs/korean/runtime" if not approved else
                         "human-approved image and metadata pass static checks; K4/K6 actual-translation execution remains required")}
    if receipt is not None:
        report["human_approval"] = receipt
    write_json(directory / "manifest.json", report)
    write_json(DOCS / f"{mode}-build.json", report)
    write_json(DOCS / f"{mode}-text-assets.json", text)
    print(f"Built {mode} 800K image; {report['disk']['free_blocks']} free blocks. Runtime verification remains required.")
    return report


if __name__ == "__main__":
    build()
