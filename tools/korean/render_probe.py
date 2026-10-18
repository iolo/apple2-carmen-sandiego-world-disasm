"""Compile multibyte renderer fixtures and an independent pixel reference."""

from .catalog import CATALOG, CONTROL_RE
from .common import BUILD, ROOT, read_json, sha256, write_json
from .encoding import GameEncoding
from .font import hgr_rows, load_bdf
from .library import assemble
from .measure_draft import units, wrap
from .renderers import build as build_renderers


def build():
    renderers = build_renderers()
    library = read_json(BUILD / "library/manifest.json")
    encoding = GameEncoding.from_catalog(read_json(CATALOG))
    indices = (0, 89, 90, 127, 128, 255, 256, 511, 512, len(encoding.characters) - 1)
    selected = [encoding.characters[i] for i in indices]
    body = ("MB " + " ".join(selected) + " ABC 123<CTRL:8D>" + "W" * 40 + "<CTRL:8D>"
            + "".join(selected[i % len(selected)] for i in range(36))
            + "<CTRL:8D>End <CTRL:80><CTRL:81><CTRL:82> " + selected[-1])
    centered = "".join(encoding.characters[i] for i in (0, 255, 512, len(encoding.characters)-1)) + " 123"
    original = (ROOT / "assets/po/D.bin").read_bytes()
    bitmaps, widths = {}, {}
    for code in range(32, 139):
        index = code - 32
        address = original[index] + 256 * original[index + 112] - 0xB900
        width, height = original[address:address+2]
        stride = (width + 6) // 7
        bitmaps[code] = [[(original[address+2+row*stride+col//7] >> (col % 7)) & 1
                          for col in range(width)] for row in range(height)]
        widths[code] = width + 1
    glyphs = load_bdf()
    for character in encoding.characters:
        bitmaps[ord(character)] = [[(row >> col) & 1 for col in range(7)] for row in hgr_rows(glyphs, character)]
        widths[ord(character)] = 8
    layout = wrap(body, widths, 16, 16, 273)
    page = bytearray([128] * 8192)

    def draw_line(value, x, y):
        for token in units(value):
            control = CONTROL_RE.fullmatch(token)
            code = int(control[1], 16) if control else ord(token)
            for row, pixels in enumerate(bitmaps[code]):
                for col, pixel in enumerate(pixels):
                    if pixel:
                        target_x, target_y = x + col, y + row
                        if not (0 <= target_x < 280 and 0 <= target_y < 192):
                            raise ValueError("Renderer fixture exceeds HGR geometry")
                        address = ((target_y & 7)*1024 + ((target_y >> 3)&7)*128 + (target_y >> 6)*40 + target_x//7)
                        page[address] ^= 1 << (target_x % 7)
            x += widths[code]
        return x

    for line, value in enumerate(layout["lines"]):
        end_x = draw_line(value, 16, 8 + line * 10)
    width = sum(widths[ord(c)] for c in centered)
    columns, remainder = divmod(width, 7)
    half = (columns // 2)*7 + remainder//2 + (4 if columns % 2 else 0)
    center_left = 140 - half
    draw_line(centered, center_left, 100)
    directory = BUILD / "render-probe"
    directory.mkdir(parents=True, exist_ok=True)
    input_bytes = bytearray(1792)
    body_bytes, center_bytes = encoding.encode(body), encoding.encode(centered)
    input_bytes[252:252+len(body_bytes)+1] = body_bytes + b"\0"
    input_bytes[1536:1536+len(center_bytes)+1] = center_bytes + b"\0"
    (directory / "strings.bin").write_bytes(input_bytes)
    (directory / "expected.hgr").write_bytes(page)
    start = (0x6000 + renderers["modules"]["N"]["bytes"] + 15) & ~15
    probes = {}
    for tag in ("N", "R", "TW"):
        module = "N" if tag == "TW" else tag
        native = read_json(BUILD / f"maps/{module}-symbols.json")
        definitions = {"K_INIT": library["symbols"]["K_INIT"], "TYPEWRITER": int(tag == "TW"),
                       "DRAW_STRING": native["N_DRAW_TEXT_XY" if tag == "TW" else ("N_DRAW_TEXT_POINTER_AT_X" if module == "N" else "R_DRAW_STRING_FROM_POINTER")],
                       "CENTER_LOOP": native["N_MEASURE_CENTERED_NEXT_CHAR" if module == "N" else "R_MEASURE_CENTERED_STRING"]}
        (directory / "render-probe-config.inc").write_text("".join(f"{k} = ${v:04X}\n" for k, v in definitions.items()))
        binary, symbols = assemble(ROOT / "src/korean/render_probe.s", directory, tag, start, 0x9200-start)
        probes[tag] = {"address": start, "bytes": len(binary), "sha256": sha256(binary), "symbols": symbols}
    typewriter_layout = wrap(body, widths, 24, 24, 126, skip_line_marker_80=True)
    typewriter_trace = []
    for line in typewriter_layout["lines"]:
        for token in units(line):
            control = CONTROL_RE.fullmatch(token)
            code = int(control[1], 16) if control else ord(token)
            typewriter_trace.append({"kind": "glyph", "id": encoding.ids[token]} if not control and ord(token)>127
                                    else {"kind": "native", "code": code})
    result = {"format": 1, "probes": probes, "body": body, "centered": centered,
              "glyph_ids": list(indices), "layout": layout, "body_end_x": end_x,
              "body_end_row": 8 + (len(layout["lines"])-1)*10, "body_terminator": 0xA0FC+len(body_bytes),
              "center_width": width, "center_left": center_left,
              "typewriter_layout": typewriter_layout, "typewriter_trace": typewriter_trace,
              "expected_hgr_sha256": sha256(page),
              "status": "synthetic RAM-only fixture; actual N/R output must match independent glyph-pixel reference"}
    write_json(directory / "manifest.json", result)
    print(f"Built N/R renderer fixtures at ${start:04X}; {len(layout['lines'])} body lines and centered text")
    return result


if __name__ == "__main__":
    build()
