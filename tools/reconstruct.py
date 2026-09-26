#!/usr/bin/env python3
"""Extract, rebuild, and check the three ProDOS Carmen World images."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from j_routes import encode_j
from case_state import encode_snapshot
from prodos_inventory import root_inventory
from c_embedded_assets import (encode_ui_text, encode_icons, encode_animation_pointers,
                               UI_START, UI_TEXT_END, UI_END, ICONS_END)
from d_font import encode_d
from hgr_page import encode_hgr_page
from rle_image import (encode_s_source, encode_o_source, encode_p_source,
                       n_picture_records)
from n_dialog import encode_dialog
from sprite_assets import encode_sprites
from s2_image_codec import encode_stream
from s2_codec import c_dictionary, encode_line


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "reconstruction" / "manifest.json"
OUTPUT = ROOT / "build"
IMAGES = {
    "disk1": {
        "input": "carmen-world-disk1.dsk",
        "output": "carmen-world-disk1.dsk",
        "volume": "CARMEN.WORLD",
        "kind": "do",
        "files": "PRODOS WORLD.SYSTEM A B C D E F G H I J K N O P Q R S T U".split(),
    },
    "disk2": {
        "input": "carmen-world-disk2.dsk",
        "output": "carmen-world-disk2.dsk",
        "volume": "CARMEN.WORLD.S2",
        "kind": "do",
        "files": "DATA.S2 FINDER.DATA".split(),
    },
    "po": {
        "input": "carmen-world.po",
        "output": "carmen-world.po",
        "volume": "CARMEN.WORLD",
        "kind": "po",
        "files": "PRODOS WORLD.SYSTEM A B C D E F G H I J K N O P Q R S T U Z S2 FINDER.ROOT FINDER.DATA".split(),
    },
}
CODE_FILES = {"WORLD.SYSTEM", "B", "C", "N", "Q", "R", "Z"}
S2_FILES = {("disk2", "DATA.S2"), ("po", "S2")}


def shift_tables_e():
    """Seven 256-byte pages of left and right 7-bit shifts, file E."""
    return b"".join(
        bytes((value << shift) & 0x7F for value in range(128))
        + bytes(value >> (7 - shift) for value in range(128))
        for shift in range(7)
    )


def run(*argv, input_bytes=None):
    proc = subprocess.run(argv, input=input_bytes, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode:
        raise RuntimeError(f"{' '.join(map(str, argv))}: {proc.stderr.decode(errors='replace')}")
    return proc.stdout


def digest(data):
    return hashlib.sha256(data).hexdigest()


def image_inventory(image, spec, allow_unused_junk):
    inventory = root_inventory(lambda block: run(
        "a2kit", "get", "-d", str(image), "-f", str(block), "-t", "block"))
    if inventory["volume"] != spec["volume"]:
        raise RuntimeError(f"{image}: volume name differs from {spec['volume']}")
    actual, expected = set(inventory["files"]), set(spec["files"])
    if actual != expected:
        raise RuntimeError(f"{image}: file coverage differs; omitted {sorted(actual - expected)}, "
                           f"missing {sorted(expected - actual)}")
    if inventory["malformed_unused_entries"] and not allow_unused_junk:
        raise RuntimeError(f"{image}: malformed unused directory entries in rebuilt image")
    return inventory


def read_manifest():
    if not MANIFEST.exists():
        raise RuntimeError("Run 'make extract' first")
    return json.loads(MANIFEST.read_text())


def extract():
    result = {"format": 1, "images": {}}
    for variant, spec in IMAGES.items():
        image = ROOT / spec["input"]
        image_record = {"input": spec["input"], "sha256": digest(image.read_bytes()),
                        "directory_inventory": image_inventory(image, spec, True), "files": {}}
        for name in spec["files"]:
            fimg = json.loads(run("a2kit", "get", "-d", str(image), "-f", name, "-t", "any"))
            content = run("a2kit", "get", "-d", str(image), "-f", name, "-t", "raw", "--trunc")
            eof = int.from_bytes(bytes.fromhex(fimg["eof"]), "little")
            if len(content) != eof:
                raise RuntimeError(f"{variant}/{name}: EOF {eof} differs from extraction length {len(content)}")
            relative = Path("assets") / variant / (name + ".bin")
            destination = ROOT / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(content)
            metadata = {key: value for key, value in fimg.items() if key != "chunks"}
            image_record["files"][name] = {
                "asset": str(relative), "sha256": digest(content), "size": len(content),
                "classification": "system" if name == "PRODOS" else "code" if name in CODE_FILES else "data",
                "file_image": metadata,
            }
        result["images"][variant] = image_record
        print(f"extracted {variant}: {len(image_record['files'])} files")
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(f"wrote {MANIFEST.relative_to(ROOT)}")


def source_path(variant, name):
    return ROOT / "src" / variant / (name + ".s")


def write_r_glyph_source(variant, destination):
    """Turn R's editable bitmap rows into labeled ca65 records."""
    source = ROOT / "assets" / "decoded" / variant / "R-glyphs.json"
    sprites = json.loads(source.read_text())["sprites"]
    if len(sprites) != 8:
        raise ValueError(f"{source}: expected eight custom glyphs")
    encoded = encode_sprites({"sprites": sprites})
    lines = ["; Generated from assets/decoded/%s/R-glyphs.json" % variant]
    for number, sprite in enumerate(sprites):
        if (sprite["character_code"] != 0x8B + number
                or sprite["load_address"] != 0x6CDE + sprite["file_offset"]):
            raise ValueError(f"{source}: incorrect glyph {number} address or character code")
        start = sprite["file_offset"]
        end = sprites[number + 1]["file_offset"] if number < 7 else len(encoded)
        lines.append(f"R_GLYPH_{number}:")
        for offset in range(start, end, 16):
            lines.append("        .byte " + ",".join(f"${byte:02X}"
                                                  for byte in encoded[offset:min(offset + 16, end)]))
    destination.write_text("\n".join(lines) + "\n")


def write_c_embedded_sources(variant, directory):
    """Emit C's editable interface strings and packed bitmaps as ca65 data."""
    decoded = ROOT / "assets" / "decoded" / variant
    ui = json.loads((decoded / "C-ui-text.json").read_text())
    ui_bytes = encode_ui_text(ui)
    lines = [f"; Generated from assets/decoded/{variant}/C-ui-text.json",
             "C_UI_TEXT_START:"]
    records = ui["records"]
    for number, record in enumerate(records):
        start = record["file_offset"]
        end = records[number + 1]["file_offset"] if number + 1 < len(records) else UI_TEXT_END - UI_START
        lines.append(f"C_UI_TEXT_{number:03d}:")
        for offset in range(start, end, 16):
            lines.append("        .byte " + ",".join(f"${byte:02X}"
                                                  for byte in ui_bytes[offset:min(offset + 16, end)]))
    lines.append(f"        .res {UI_END - UI_TEXT_END}, $00")
    (directory / "c_ui_text.inc").write_text("\n".join(lines) + "\n")

    icons = json.loads((decoded / "C-icons.json").read_text())
    icon_bytes = encode_icons(icons)
    records = icons["sprites"]
    lines = [f"; Generated from assets/decoded/{variant}/C-icons.json",
             "C_ICON_RECORDS:"]
    for number, record in enumerate(records):
        start = record["file_offset"]
        end = records[number + 1]["file_offset"] if number + 1 < len(records) else ICONS_END - UI_END
        lines.append(f"C_ICON_{number:02d}:")
        stride = (record["width"] + 6) // 7
        body_end = start + 2 + stride * record["height"]
        lines.append(f"        .byte ${record['width']:02X},${record['height']:02X} ; width, height")
        for offset in range(start + 2, body_end, stride):
            lines.append("        .byte " + ",".join(f"${byte:02X}"
                                                  for byte in icon_bytes[offset:offset + stride]))
        if body_end < end:
            lines.append(f"C_ICON_{number:02d}_RETAINED_TAIL:")
            lines.append("        ; Outside the declared height; not read by the glyph row loops.")
            lines.append("        .byte " + ",".join(f"${byte:02X}"
                                                  for byte in icon_bytes[body_end:end]))
    (directory / "c_icons.inc").write_text("\n".join(lines) + "\n")

    pointers = json.loads((decoded / "C-animation-pointers.json").read_text())
    t_source = json.loads((decoded / "T-sprites.json").read_text())
    u_source = json.loads((decoded / "U-sprites.json").read_text())
    lows, highs = encode_animation_pointers(pointers, t_source, u_source)
    for suffix, values in (("lo", lows), ("hi", highs)):
        lines = [f"; Generated from assets/decoded/{variant}/C-animation-pointers.json"]
        for offset in range(0, len(values), 8):
            lines.append("        .byte " + ",".join(f"${byte:02X}"
                                                  for byte in values[offset:offset + 8]))
        (directory / f"c_animation_ptr_{suffix}.inc").write_text("\n".join(lines) + "\n")


def write_n_dialog_source(destination):
    """Emit the 800 KB N save message from its editable text segments."""
    source = ROOT / "assets" / "decoded" / "po" / "N-save-dialog.json"
    data = encode_dialog(json.loads(source.read_text()))
    lines = ["; Generated from assets/decoded/po/N-save-dialog.json"]
    for offset in range(0, len(data), 16):
        lines.append("        .byte " + ",".join(
            f"${byte:02X}" for byte in data[offset:offset + 16]))
    destination.write_text("\n".join(lines) + "\n")


def assemble(variant, name, addr):
    source = source_path(variant, name)
    if not source.exists():
        return None
    with tempfile.TemporaryDirectory(prefix="carmen-asm-") as directory:
        directory = Path(directory)
        config = directory / "link.cfg"
        config.write_text(
            f"MEMORY {{ RAM: start = ${addr:04X}, size = ${0x10000 - addr:04X}, file = %O; }}\n"
            "SEGMENTS { CODE: load = RAM, type = ro; }\n"
        )
        obj = directory / "file.o"
        binary = directory / "file.bin"
        if name == "R":
            write_r_glyph_source(variant, directory / "r_glyphs.inc")
        if name == "C":
            write_c_embedded_sources(variant, directory)
        if variant == "po" and name == "N":
            write_n_dialog_source(directory / "n_dialog.inc")
        run("ca65", str(source), "-I", str(directory), "-o", str(obj))
        run("ld65", "-C", str(config), str(obj), "-o", str(binary))
        return binary.read_bytes()


def content_for(variant, name, record):
    asset = ROOT / record["asset"]
    content = asset.read_bytes()
    if digest(content) != record["sha256"]:
        raise RuntimeError(f"{asset}: extracted asset hash changed")
    if (variant, name) in S2_FILES:
        content = pack_s2(variant)
    if name == "A":
        source = ROOT / "assets" / "decoded" / variant / "A-hgr.json"
        content = encode_hgr_page(json.loads(source.read_text()))
    if name == "E":
        content = shift_tables_e()
    if name == "D":
        source = ROOT / "assets" / "decoded" / variant / "D-font.json"
        content = encode_d(json.loads(source.read_text()))
    if name == "F":
        content = pack_f(variant)
    if name == "H":
        content = pack_h(variant)
    if name == "G":
        content = pack_g(variant)
    if name in ("I", "K"):
        content = pack_text(variant, name)
    if name == "J":
        content = pack_j(variant)
    if name == "S":
        content = pack_s(variant)
    if name == "O":
        content = pack_o(variant)
    if name == "P":
        content = pack_p(variant)
    if name in ("T", "U"):
        source = ROOT / "assets" / "decoded" / variant / f"{name}-sprites.json"
        content = encode_sprites(json.loads(source.read_text()))
    if record["classification"] == "code" and not source_path(variant, name).exists():
        raise RuntimeError(f"{variant}/{name}: missing ca65 source")
    if source_path(variant, name).exists():
        aux = int.from_bytes(bytes.fromhex(record["file_image"]["aux"]), "little")
        content = assemble(variant, name, aux)
    if len(content) != record["size"]:
        raise RuntimeError(f"{variant}/{name}: build length {len(content)} != {record['size']}")
    return content


def pack_s2(variant):
    directory = ROOT / "assets" / "s2_source" / variant
    records = sorted(directory.glob("[0-9][0-9].json"))
    if len(records) != 30:
        raise RuntimeError(f"{variant}: expected 30 S2 text sources, found {len(records)}")
    dictionary_variant = "disk1" if variant == "disk2" else "po"
    _, words = c_dictionary((ROOT / "assets" / dictionary_variant / "C.bin").read_bytes())
    offsets = [192]
    chunks = []
    for path in records:
        lines = json.loads(path.read_text())["lines"]
        encoded = b"\0".join(encode_line(line, words) for line in lines)
        if not encoded.endswith(b"\0\0"):
            raise RuntimeError(f"{path}: S2 text must end with two NUL bytes")
        image_source = path.with_name(path.stem + "-image.json")
        binary = encode_stream(json.loads(image_source.read_text()))
        text_end = len(encoded) + 2
        chunks.append(text_end.to_bytes(2, "little") + encoded + binary)
        offsets.append(offsets[-1] + len(chunks[-1]))
    table = b"".join(offset.to_bytes(3, "little") for offset in offsets).ljust(192, b"\0")
    return table + b"".join(chunks)


def pack_s(variant):
    """Join the four fixed-address compressed HGR records in S."""
    directory = ROOT / "assets" / "s_source" / variant
    lengths = (0x03E0, 0x03C0, 0x07C0, 0x0A60)
    chunks = []
    for number, expected in enumerate(lengths):
        path = directory / f"{number:02d}.json"
        source = json.loads(path.read_text())
        chunks.append(encode_s_source(source, number,
                                      0x7800 + sum(lengths[:number]), expected))
    return b"".join(chunks)


def pack_o(variant):
    """Join O's four fixed-address compressed HGR records."""
    directory = ROOT / "assets" / "o_source" / variant
    n_records = n_picture_records(assemble(variant, "N", 0x6000), variant)
    records = ((2, 0x0168), (4, 0x04C8), (3, 0x0430), (1, 0x00A0))
    chunks = []
    for number, expected in records:
        path = directory / f"{number:02d}.json"
        source = json.loads(path.read_text())
        chunks.append(encode_o_source(source, n_records[number], expected))
    return b"".join(chunks)


def pack_p(variant):
    """Rebuild P's two overlapping pictures from one editable byte stream."""
    source = ROOT / "assets" / "p_source" / variant / "P.json"
    records = n_picture_records(assemble(variant, "N", 0x6000), variant)
    return encode_p_source(json.loads(source.read_text()), records)


def pack_f(variant):
    """Rebuild the 13-slot detective roster from its decoded JSON source."""
    source = ROOT / "assets" / "decoded" / variant / "F.json"
    roster = json.loads(source.read_text())
    if roster["record_size"] != 19 or len(roster["slots"]) != 13:
        raise RuntimeError(f"{source}: expected thirteen 19-byte records")
    chunks = []
    for slot, record in enumerate(roster["slots"]):
        if record["slot"] != slot or record["offset"] != slot * 19:
            raise RuntimeError(f"{source}: incorrect slot offset for {slot}")
        if record["empty"]:
            if record["name"] or any(record[key] is not None for key in
                                    ("rank_index", "cases_solved", "saved_case")):
                raise RuntimeError(f"{source}: empty slot {slot} has content")
            chunks.append(b"\xff" * 19)
        else:
            name = record["name"].encode("ascii")
            if not name or len(name) > 16 or b"\xff" in name:
                raise RuntimeError(f"{source}: invalid name in slot {slot}")
            status = [record[key] for key in ("rank_index", "cases_solved", "saved_case")]
            if any(not isinstance(value, int) or not 0 <= value <= 255 for value in status):
                raise RuntimeError(f"{source}: slot {slot} needs three byte values")
            chunks.append(name.ljust(16, b"\xff") + bytes(status))
    tail = bytes.fromhex(roster["tail_hex"])
    result = b"".join(chunks) + tail
    if len(result) != 256:
        raise RuntimeError(f"{source}: rebuilt length {len(result)} is not 256")
    return result


def pack_g(variant):
    """Rebuild G's sixteen FF-padded hall-of-fame name slots."""
    source = ROOT / "assets" / "decoded" / variant / "G.json"
    data = json.loads(source.read_text())
    if data["record_size"] != 16 or len(data["slots"]) != 16:
        raise RuntimeError(f"{source}: expected sixteen 16-byte records")
    records = []
    for slot, record in enumerate(data["slots"]):
        if record["slot"] != slot:
            raise RuntimeError(f"{source}: incorrect slot order at {slot}")
        name = record["name"]
        if name is None:
            records.append(b"\xff" * 16)
            continue
        if not isinstance(name, str) or not 1 <= len(name) <= 16:
            raise RuntimeError(f"{source}: invalid name in slot {slot}")
        encoded = name.encode("ascii")
        if any(byte < 32 or byte > 126 for byte in encoded):
            raise RuntimeError(f"{source}: nonprintable name in slot {slot}")
        records.append(encoded.ljust(16, b"\xff"))
    return b"".join(records)


def pack_h(variant):
    """Rebuild thirteen pages from named case fields or FF markers."""
    source = ROOT / "assets" / "decoded" / variant / "H.json"
    slots = json.loads(source.read_text())["slots"]
    if len(slots) != 13:
        raise RuntimeError(f"{source}: expected thirteen saved-case slots")
    pages = []
    for slot, record in enumerate(slots):
        if record["slot"] != slot:
            raise RuntimeError(f"{source}: incorrect slot order at {slot}")
        if record["unused"]:
            if record["case_state"] is not None:
                raise RuntimeError(f"{source}: unused slot {slot} has a snapshot")
            pages.append(b"\xff" * 256)
        else:
            snapshot = encode_snapshot(record["case_state"])
            pages.append(snapshot + b"\0" * 223)
    return b"".join(pages)


def pack_text(variant, name):
    """Rebuild a NUL-delimited ASCII file from editable string sources."""
    source = ROOT / "assets" / "text_source" / variant / (name + ".json")
    strings = json.loads(source.read_text())["strings"]
    if not isinstance(strings, list) or not strings:
        raise RuntimeError(f"{source}: expected a nonempty string list")
    chunks = []
    for index, value in enumerate(strings):
        if not isinstance(value, str):
            raise RuntimeError(f"{source}: string {index} is not text")
        encoded = value.encode("ascii")
        if any(byte < 32 or byte > 126 for byte in encoded):
            raise RuntimeError(f"{source}: string {index} contains a control byte")
        chunks.append(encoded + b"\0")
    return b"".join(chunks)


def pack_j(variant):
    """Rebuild J's eight reciprocal city-route graphs."""
    base = ROOT / "assets" / "decoded" / variant
    cities = [entry["name"] for entry in json.loads((base / "C-names.json").read_text())["cities"]]
    return encode_j(json.loads((base / "J-routes.json").read_text()), cities)


def make_fimg(name, record, content):
    metadata = dict(record["file_image"])
    metadata["full_path"] = name
    chunk_len = metadata["chunk_len"]
    metadata["chunks"] = {
        str(index): content[offset:offset + chunk_len].ljust(chunk_len, b"\0").hex().upper()
        for index, offset in enumerate(range(0, len(content), chunk_len))
    }
    return (json.dumps(metadata) + "\n").encode()


def build():
    manifest = read_manifest()
    OUTPUT.mkdir(exist_ok=True)
    for variant, spec in IMAGES.items():
        target = OUTPUT / spec["output"]
        # Assemble before touching the existing output, then replace it only
        # after every file was written successfully.
        file_images = []
        for name in spec["files"]:
            record = manifest["images"][variant]["files"][name]
            file_images.append((name, make_fimg(name, record, content_for(variant, name, record))))
        with tempfile.TemporaryDirectory(prefix=f"carmen-{variant}-", dir=OUTPUT) as directory:
            pending = Path(directory) / spec["output"]
            command = ["a2kit", "mkdsk", "-o", "prodos", "-v", spec["volume"], "-t", spec["kind"]]
            if spec["kind"] == "po":
                command += ["-k", "3.5in-apple-800"]
            run(*command, "-d", str(pending))
            for name, file_image in file_images:
                run("a2kit", "put", "-d", str(pending), "-f", name, "-t", "any",
                    input_bytes=file_image)
            pending.replace(target)
        print(f"built {target.relative_to(ROOT)}")


def check():
    manifest = read_manifest()
    errors = []
    for variant, spec in IMAGES.items():
        target = OUTPUT / spec["output"]
        original = ROOT / spec["input"]
        try:
            if digest(original.read_bytes()) != manifest["images"][variant]["sha256"]:
                raise RuntimeError(f"{original}: source image changed since extraction")
            image_inventory(original, spec, True)
            if target.exists():
                image_inventory(target, spec, False)
        except RuntimeError as exc:
            errors.append(str(exc))
        if not target.exists():
            errors.append(f"missing {target}")
            continue
        for name in spec["files"]:
            record = manifest["images"][variant]["files"][name]
            try:
                content = run("a2kit", "get", "-d", str(target), "-f", name, "-t", "raw", "--trunc")
                metadata = json.loads(run("a2kit", "get", "-d", str(target), "-f", name, "-t", "any"))
                if digest(content) != record["sha256"]:
                    errors.append(f"{variant}/{name}: content differs")
                for key in ("eof", "fs_type", "aux"):
                    if metadata[key] != record["file_image"][key]:
                        errors.append(f"{variant}/{name}: {key} differs")
            except RuntimeError as exc:
                errors.append(str(exc))
        print(f"checked {variant}: {len(spec['files'])} files")
    if errors:
        raise RuntimeError("\n".join(errors))
    print("all rebuilt game files match their source files and required ProDOS metadata")


def inventory():
    manifest = read_manifest()
    for variant, image in manifest["images"].items():
        print(f"{variant}: {image['input']}")
        for name, record in image["files"].items():
            aux = int.from_bytes(bytes.fromhex(record["file_image"]["aux"]), "little")
            source = "assembly" if source_path(variant, name).exists() else "asset"
            print(f"  {name:12} {record['size']:6} ${aux:04X} {record['classification']:6} {source}")


def smoke():
    import shutil
    if shutil.which("mame") is None:
        raise RuntimeError("mame is required for the smoke target")
    if not (OUTPUT / IMAGES["disk1"]["output"]).exists():
        raise RuntimeError("Run 'make build' first")
    command = ["mame", "apple2e", "-flop1", str(OUTPUT / IMAGES["disk1"]["output"]),
               "-flop2", str(OUTPUT / IMAGES["disk2"]["output"]),
               "-video", "none", "-sound", "none", "-nothrottle", "-seconds_to_run", "20"]
    rompath = os.environ.get("MAME_ROMPATH")
    if not rompath:
        sibling = ROOT.parent / "a2x" / "mame" / "roms"
        if sibling.is_dir():
            rompath = str(sibling)
    if rompath:
        command += ["-rompath", rompath]
    print("running", " ".join(command), flush=True)
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
    print(result.stdout.decode(errors="replace"))
    if result.returncode:
        raise RuntimeError(f"MAME exited with {result.returncode}")
    print("MAME ran the rebuilt floppy pair for 20 emulated seconds; gameplay remains to be checked interactively")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["extract", "build", "check", "inventory", "smoke"])
    args = parser.parse_args()
    try:
        globals()[args.command]()
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
        print(exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
