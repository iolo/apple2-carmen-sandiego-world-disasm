"""Build bounded, disposable RAM-only probes for both original HGR renderers."""

import subprocess

from .common import BUILD, ROOT, read_json, sha256, write_json
from .font import hgr_rows, load_bdf


def main():
    glyphs = load_bdf()
    work = BUILD / "probe"
    work.mkdir(parents=True, exist_ok=True)
    for char, name in (("한", "han"), ("글", "geul")):
        rows = hgr_rows(glyphs, char)
        (work / f"probe-{name}.inc").write_text(".byte " + ",".join(f"${b:02X}" for b in rows) + "\n")
    (work / "probe.cfg").write_text("MEMORY { RAM: start=$9200, size=$0600, file=%O; }\n"
                                    "SEGMENTS { CODE: load=RAM, type=ro; }\n")
    report = {"format": 1, "load_address": 0x9200, "end_exclusive_limit": 0x9800,
              "purpose": "synthetic renderer feasibility only; no game image or translation is patched",
              "glyphs": ["한", "글"], "probes": {}}
    for module, label in (("N", "N_DRAW_TEXT_POINTER_AT_X"), ("R", "R_DRAW_STRING_FROM_POINTER")):
        symbols = read_json(BUILD / f"maps/{module}-symbols.json")
        (work / "probe-config.inc").write_text(f"DRAW_STRING := ${symbols[label]:04X}\n")
        subprocess.run(["ca65", "-g", str(ROOT / "src/korean/probe.s"), "-I", str(work),
                        "-o", str(work / "probe.o")], check=True)
        binary = work / f"{module}.bin"
        debug = work / f"{module}.dbg"
        subprocess.run(["ld65", "-C", str(work / "probe.cfg"), str(work / "probe.o"),
                        "-o", str(binary), "--dbgfile", str(debug)], check=True)
        # ld65 debug symbols are emitted in the same syntax as capacity maps.
        import re
        match = re.search(r'name="PROBE_DONE"[^\n]*\bval=(0x[0-9A-Fa-f]+)', debug.read_text())
        if not match:
            raise ValueError("Missing probe completion symbol")
        report["probes"][module] = {"path": str(binary.relative_to(ROOT)), "bytes": binary.stat().st_size,
                                     "sha256": sha256(binary.read_bytes()), "done": int(match[1], 16),
                                     "renderer_address": symbols[label]}
    write_json(work / "manifest.json", report)
    print(f"Built N/R synthetic probes at $9200 ({report['probes']['N']['bytes']} bytes each)")


if __name__ == "__main__":
    main()
