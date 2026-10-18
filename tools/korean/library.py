"""Assemble the resident decoder/font library and exact native lookup tables."""

import re
import subprocess

from .catalog import CATALOG
from .common import BUILD, ROOT, read_json, sha256, write_json
from .encoding import GameEncoding, TRAILS, compile_fixtures


def assemble(source, directory, stem, address, capacity):
    directory.mkdir(parents=True, exist_ok=True)
    config = directory / f"{stem}.cfg"
    config.write_text(f"MEMORY {{ RAM: start=${address:04X}, size=${capacity:04X}, file=%O; }}\n"
                      "SEGMENTS { CODE: load=RAM, type=ro; }\n")
    obj, binary, debug = (directory / f"{stem}.{suffix}" for suffix in ("o", "bin", "dbg"))
    subprocess.run(["ca65", "-g", str(source), "-I", str(directory), "-o", str(obj)], check=True)
    subprocess.run(["ld65", "-C", str(config), str(obj), "-o", str(binary), "--dbgfile", str(debug)], check=True)
    symbols = {}
    for line in debug.read_text().splitlines():
        if line.startswith("sym\t"):
            name = re.search(r'name="([^"]+)"', line)
            value = re.search(r'\bval=(0x[0-9A-Fa-f]+|[0-9]+)', line)
            if name and value:
                symbols[name[1]] = int(value[1], 0)
    write_json(directory / f"{stem}-symbols.json", symbols)
    return binary.read_bytes(), symbols


def build():
    report = compile_fixtures()
    encoding = GameEncoding.from_catalog(read_json(CATALOG))
    directory = BUILD / "library"
    directory.mkdir(parents=True, exist_ok=True)
    font_bytes = report["font_bytes"]
    if not 4096 < font_bytes <= 10496:
        raise ValueError("Font does not fit the verified two-region candidate")
    # Do not silently extend the particular footprint measured by the live
    # font-residency run. A changed catalog must repeat that experiment first.
    residency = read_json(ROOT / "docs/korean/runtime/font-residency.json")
    if residency["status"] != "pass" or residency["font_bytes"] != font_bytes or residency["font_sha256"] != report["font_sha256"]:
        raise ValueError("Current font lacks matching native residency evidence")
    (directory / "library-config.inc").write_text(f"K_FONT_BYTES = ${font_bytes:04X}\n")
    data, symbols = assemble(ROOT / "src/korean/library.s", directory, "KL", 0x9200, 0x500)
    trails = bytes(TRAILS.index(b) if b in TRAILS else 255 for b in range(256))
    rows = [i * len(TRAILS) * 8 for i in range(111)]
    lo = bytes(v & 255 if v < font_bytes else 255 for v in rows)
    hi = bytes(v >> 8 if v < font_bytes else 255 for v in rows)
    for name, payload in (("trail-map", trails), ("lead-lo", lo), ("lead-hi", hi)):
        (directory / (name + ".bin")).write_bytes(payload)
    result = {"format": 1, "catalog_sha256": report["catalog_sha256"], "font_sha256": report["font_sha256"],
              "font_bytes": font_bytes, "address": 0x9200, "bytes": len(data), "sha256": sha256(data),
              "symbols": symbols,
              "lookup_tables": {"trail-map": {"address": 0xD900, "bytes": len(trails)},
                                "lead-lo": {"address": 0xDA00, "bytes": len(lo)},
                                "lead-hi": {"address": 0xDA70, "bytes": len(hi)}},
              "status": "assembled RAM library; exact runtime evidence is recorded separately under docs/korean/runtime"}
    write_json(directory / "manifest.json", result)
    source = b"\0" + encoding.encode("".join(encoding.characters)) + b"\0"
    (directory / "all-glyphs.bin").write_bytes(source)
    result["probes"] = {}
    for mode, pointer in (("C2", 0xC2), ("C6", 0xC6)):
        definitions = {"K_INIT": symbols["K_INIT"], "K_READ": symbols[f"K_READ_{mode}"],
                       "K_FETCH": symbols["K_FETCH"], "K_PENDING": symbols["K_PENDING"],
                       "K_ERROR": symbols["K_ERROR"], "SOURCE_PTR": pointer,
                       "GLYPH_COUNT": len(encoding.characters)}
        (directory / "native-probe-config.inc").write_text("".join(f"{key} = ${value:04X}\n" for key, value in definitions.items()))
        probe, probe_symbols = assemble(ROOT / "src/korean/library_probe.s", directory, f"probe-{mode}", 0x8F00, 0x300)
        result["probes"][mode] = {"bytes": len(probe), "sha256": sha256(probe), "symbols": probe_symbols}
    write_json(directory / "manifest.json", result)
    print(f"Assembled {len(data)}-byte library at $9200; {len(encoding.characters)} glyphs")
    return result


if __name__ == "__main__":
    build()
