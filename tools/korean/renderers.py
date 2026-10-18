"""Build strictly bounded N/R text hooks, without patching a game disk."""

from .common import BUILD, ROOT, read_json, sha256, write_json
from .library import assemble, build as build_library


def word(value):
    return int(value).to_bytes(2, "little")


def branch(opcode, site, target):
    offset = target - site - 2
    if not -128 <= offset <= 127:
        raise ValueError("Original branch target out of range")
    return bytes((opcode, offset & 255))


def build():
    library = build_library()
    native_library = read_json(ROOT / "docs/korean/runtime/native-font.json")
    if (native_library["status"] != "pass" or native_library["library_sha256"] != library["sha256"]
            or native_library["font_sha256"] != library["font_sha256"]
            or native_library.get("probe_binaries") != {mode: probe["sha256"] for mode, probe in library["probes"].items()}):
        raise ValueError("Current library lacks matching native decoder/font probe evidence")
    results = {}
    for module in ("N", "R"):
        native = read_json(BUILD / f"maps/{module}-symbols.json")
        directory = BUILD / "renderers" / module
        directory.mkdir(parents=True, exist_ok=True)
        original = (ROOT / f"assets/po/{module}.bin").read_bytes()
        end = 0x6000 + len(original)
        limit = 0x9200 if module == "N" else 0x7800
        aliases = (dict(SCAN_SITE="N_SCAN_NEXT_TEXT_CHAR", SCAN_NONZERO="N_MEASURE_PRINTABLE_CHAR",
                        CENTER_SITE="N_MEASURE_CENTERED_NEXT_CHAR", CENTER_ZERO="N_HALVE_CENTERED_TEXT_WIDTH",
                        DRAW_GLYPH="N_DRAW_GLYPH_CHAR", CHAR_INDEX="N_PREPARE_GLYPH_INDEX",
                        CHAR_HEADER="N_READ_GLYPH_HEADER", BACKTRACK_READY="N_RESTORE_TEXT_RUN_START",
                        SEPARATOR_NEXT="N_CHECK_NEXT_TEXT_SPACE", TW_SCAN_SITE="N_TYPEWRITER_SCAN_CHAR",
                        TW_SCAN_NONZERO="N_TYPEWRITER_MEASURE_GLYPH", TW_BACKTRACK_READY="N_TYPEWRITER_RESTORE_CURSOR",
                        TW_SEPARATOR_NEXT="N_TYPEWRITER_SKIP_SPACES") if module == "N" else
                   dict(SCAN_SITE="R_SCAN_STRING_CHAR", SCAN_NONZERO="R_MEASURE_STRING_CHAR",
                        CENTER_SITE="R_MEASURE_CENTERED_STRING", CENTER_ZERO="R_HALVE_STRING_WIDTH",
                        DRAW_GLYPH="R_DRAW_GLYPH", CHAR_INDEX="R_LOOKUP_GLYPH_INDEX",
                        CHAR_HEADER="R_READ_GLYPH_SIZE", BACKTRACK_READY="R_DRAW_MEASURED_LINE",
                        SEPARATOR_NEXT="R_BEGIN_NEXT_STRING_LINE"))
        values = {key: native[label] for key, label in aliases.items()}
        values.update({key: library["symbols"][key] for key in
                       ("K_READ_C2", "K_READ_C6", "K_FETCH", "K_PENDING", "K_SCAN_FIRST_LO", "K_SCAN_FIRST_HI", "K_HARD_BREAK")})
        values["MODE_N"] = int(module == "N")
        (directory / "render-config.inc").write_text("".join(f"{key} = ${value:04X}\n" for key, value in values.items()))
        extension, hooks = assemble(ROOT / "src/korean/render_hooks.s", directory, "hooks", end, limit - end)
        patched = bytearray(original + extension)
        spans = []

        def replace(address, expected, replacement, purpose):
            offset = address - 0x6000
            if bytes(patched[offset:offset + len(expected)]) != expected:
                raise ValueError(f"{module}/{purpose}: original instruction contract differs at ${address:04X}")
            if len(replacement) > len(expected) or any(max(address, s["address"]) < min(address + len(expected), s["address"] + s["bytes"]) for s in spans):
                raise ValueError("Overlapping/oversize renderer patch")
            replacement += b"\xEA" * (len(expected) - len(replacement))
            patched[offset:offset + len(expected)] = replacement
            spans.append({"address": address, "bytes": len(expected), "original_hex": expected.hex(),
                          "patched_hex": replacement.hex(), "purpose": purpose})

        def jump(address, expected, hook, purpose):
            replace(address, expected, b"\x4C" + word(hooks[hook]), purpose)

        def scanner(site, nonzero, hook, purpose):
            jump(site, b"\xA1\xC6" + branch(0xD0, site + 2, nonzero), hook, purpose)

        scanner(values["SCAN_SITE"], values["SCAN_NONZERO"], "HOOK_SCAN", "multibyte line measurement")
        site = values["CENTER_SITE"]
        jump(site, b"\xA1\xC2" + branch(0xF0, site + 2, values["CENTER_ZERO"]), "HOOK_CENTER", "multibyte centered measurement")
        site = native["N_DRAW_NEXT_TEXT_CHAR" if module == "N" else "R_DRAW_NEXT_LINE_CHAR"]
        replace(site, b"\xA1\xC2\x20" + word(values["DRAW_GLYPH"]), b"\x20" + word(hooks["HOOK_DRAW"]), "multibyte glyph drawing")
        site = native["N_PREPARE_GLYPH_CHAR" if module == "N" else "R_LOOKUP_GLYPH"]
        jump(site, b"\x38\xE9\x20", "HOOK_CHAR", "shared font cache; preserve direct glyph-index ABI")
        site = native["N_BACKTRACK_TO_WORD_SPACE" if module == "N" else "R_BACKTRACK_TO_WORD_BREAK"]
        jump(site, b"\xA1\xC6\xC9\x20" + branch(0xF0, site + 4, values["BACKTRACK_READY"]), "HOOK_BACKTRACK", "bounded word backtracking")
        site = native["N_SKIP_TEXT_SEPARATOR" if module == "N" else "R_SKIP_LINE_SEPARATOR"]
        jump(site, b"\xE6\xC6" + branch(0xD0, site + 2, values["SEPARATOR_NEXT"]), "HOOK_SEPARATOR", "retain glyph after hard line break")
        if module == "N":
            scanner(values["TW_SCAN_SITE"], values["TW_SCAN_NONZERO"], "HOOK_TW_SCAN", "multibyte typewriter measurement")
            site = native["N_TYPEWRITER_DRAW_NEXT_CHAR"] + 5
            replace(site, b"\xA1\xC2\x20" + word(values["DRAW_GLYPH"]), b"\x20" + word(hooks["HOOK_DRAW"]), "multibyte typewriter drawing")
            site = native["N_TYPEWRITER_BACKTRACK_SPACE"]
            jump(site, b"\xA1\xC6\xC9\x20" + branch(0xF0, site + 4, values["TW_BACKTRACK_READY"]), "HOOK_TW_BACKTRACK", "bounded typewriter backtracking")
            site = native["N_TYPEWRITER_ADVANCE_BREAK"]
            jump(site, b"\xE6\xC6" + branch(0xD0, site + 2, values["TW_SEPARATOR_NEXT"]), "HOOK_TW_SEPARATOR", "retain glyph after typewriter hard break")
        output = directory / f"{module}.bin"
        output.write_bytes(patched)
        results[module] = {"path": str(output.relative_to(ROOT)), "bytes": len(patched), "extension_bytes": len(extension),
                           "limit_exclusive": limit, "sha256": sha256(patched), "original_sha256": sha256(original),
                           "hooks": hooks, "patches": spans}
        print(f"{module}: {len(extension)} helper bytes, {len(spans)} validated instruction spans")
    manifest = {"format": 1, "library_sha256": library["sha256"], "modules": results,
                "status": "RAM fixtures only; native renderer tests and synthetic game integration pending"}
    write_json(BUILD / "renderers/manifest.json", manifest)
    return manifest


if __name__ == "__main__":
    build()
