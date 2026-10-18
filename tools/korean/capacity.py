"""Measure original file/record sizes and ProDOS bitmap; emit assembler symbols.

This report distinguishes an address gap from RAM proved free at runtime.
No zero-filled memory scan is used as evidence of ownership.
"""

import re
import subprocess
import sys
import tempfile

from .common import BUILD, DOCS, ROOT, original_inputs, read_json, sha256, write_json

# Original tools use sibling imports. Do not change their build/import contract.
sys.path.insert(0, str(ROOT / "tools"))
from reconstruct import write_c_embedded_sources, write_n_dialog_source, write_r_glyph_source
from extract_assets import render_s2_line, s2_index
from s2_codec import c_dictionary


def symbols(module, directory):
    """Link original sources with debug information; retain all named addresses."""
    source = ROOT / "src/po" / f"{module}.s"
    manifest = read_json(ROOT / "reconstruction/manifest.json")["images"]["po"]["files"][module]
    address = int.from_bytes(bytes.fromhex(manifest["file_image"]["aux"]), "little")
    with tempfile.TemporaryDirectory(prefix="carmen-korean-map-") as temporary:
        from pathlib import Path
        work = Path(temporary)
        if module == "C":
            write_c_embedded_sources("po", work)
        if module == "R":
            write_r_glyph_source("po", work / "r_glyphs.inc")
        if module == "N":
            write_n_dialog_source(work / "n_dialog.inc")
        config = work / "link.cfg"
        config.write_text(f"MEMORY {{ RAM: start=${address:04X}, size=${0x10000-address:04X}, file=%O; }}\n"
                          "SEGMENTS { CODE: load=RAM, type=ro; }\n")
        binary = work / "module.bin"
        debug = directory / f"{module}.dbg"
        subprocess.run(["ca65", "-g", str(source), "-I", str(work), "-o", str(work / "module.o")], check=True)
        subprocess.run(["ld65", "-C", str(config), str(work / "module.o"), "-o", str(binary),
                        "--dbgfile", str(debug)], check=True)
        if binary.read_bytes() != (ROOT / manifest["asset"]).read_bytes():
            raise ValueError(f"{module}: debug build does not reproduce original")
    result = {}
    for line in debug.read_text().splitlines():
        if not line.startswith("sym\t"):
            continue
        name = re.search(r'name="([^"]+)"', line)
        value = re.search(r'\bval=(0x[0-9A-Fa-f]+|[0-9]+)', line)
        if name and value:
            result[name[1]] = int(value[1], 0)
    write_json(directory / f"{module}-symbols.json", dict(sorted(result.items())))
    return result


def disk_capacity(path):
    disk = path.read_bytes()
    total = int.from_bytes(disk[2 * 512 + 41:2 * 512 + 43], "little")
    bitmap = int.from_bytes(disk[2 * 512 + 39:2 * 512 + 41], "little") * 512
    if len(disk) != total * 512 or bitmap + (total + 7) // 8 > len(disk):
        raise ValueError("Unexpected ProDOS block geometry")
    free = [block for block in range(total)
            if disk[bitmap + block // 8] & (0x80 >> (block % 8))]
    return {"path": str(path.relative_to(ROOT)), "sha256": sha256(disk),
            "total_blocks": total, "free_blocks": len(free), "free_bytes": len(free) * 512,
            "evidence": "volume header block 2 and MSB-first ProDOS allocation bitmap",
            "note": "New files also require index blocks and directory entries."}


def measure():
    identities = original_inputs()
    directory = BUILD / "maps"
    directory.mkdir(parents=True, exist_ok=True)
    for module in ("WORLD.SYSTEM", "B", "C", "N", "R"):
        symbols(module, directory)
    m = read_json(ROOT / "reconstruction/manifest.json")["images"]["po"]["files"]
    cdata = (ROOT / "assets/po/C.bin").read_bytes()
    _, words = c_dictionary(cdata)
    s2 = (ROOT / "assets/po/S2.bin").read_bytes()
    categories = read_json(ROOT / "assets/decoded/po/N-city-clue-counts.json")["cities"]
    records = []
    for item in s2_index(s2):
        record = s2[item["start"]:item["end"]]
        end = int.from_bytes(record[:2], "little")
        lines = record[2:end].split(b"\0")
        category_maxima = [max(len(lines[line["number"]]) + 1 for line in group["lines"])
                           for group in categories[item["number"]]["groups"] if group["lines"]]
        records.append({"city": item["number"], "record_bytes": len(record),
                        "stored_text_bytes": end - 2, "image_bytes": len(record) - end,
                        "longest_stored_line_bytes": max(map(len, lines)),
                        "longest_description_with_nul": max(len(line) + 1 for line in lines[:3]),
                        "three_selected_distinct_category_clues_bytes": sum(sorted(category_maxima, reverse=True)[:3]),
                        "longest_expanded_line_bytes": max(len(render_s2_line(line, words,
                            {"#": "she", "@": "her", "^": "her"})) for line in lines)})
    files = {name: {"file_bytes": m[name]["size"], "metadata_address":
                   int.from_bytes(bytes.fromhex(m[name]["file_image"]["aux"]), "little"),
                   "sha256": m[name]["sha256"]} for name in ("C", "D", "N", "R", "S2", "I", "K")}
    return {"format": 1, "original_inputs": identities, "files": files,
            "disks": [disk_capacity(ROOT / "carmen-world.po"), disk_capacity(ROOT / "build/carmen-world.po")],
            "s2": records,
            "limits": {"city_description_copy_including_nul": 256,
                       "main_s2_text_read_before_O": 0xA700 - 0xA000,
                       "aux_K_boot_copy": 4096, "aux_I_boot_copy": 4096,
                       "C_UI_region_including_padding": 3072,
                       "D_before_ProDOS_MLI": 1536,
                       "common_main_probe_gap": {"start": 0x9200, "end_exclusive": 0x9800,
                           "bytes": 1536, "status": "candidate; runtime watch and lifecycle checks required"}},
            "symbols": "build/korean/maps/*-symbols.json",
            "remaining": ["Measure bank ownership through intro, S2 reads, image display and save/restore",
                          "Do not count unmeasured RAM gaps as approved font capacity",
                          "Re-measure using the complete translation draft before human review"]}


def main():
    report = measure()
    write_json(DOCS / "original-capacity.json", report)
    print(f"Measured {len(report['s2'])} S2 records; wrote docs/korean/original-capacity.json")


if __name__ == "__main__":
    main()
