"""Native clock pixels for every hour and weekday against an independent font reference."""

import argparse

from . import test_mode
import shutil

from .catalog import CATALOG
from .common import BUILD, DOCS, ROOT, read_json, sha256, write_json
from .encoding import GameEncoding
from .font import hgr_rows, load_bdf
from .library import assemble
from .synthetic_test import launch


def reference(day, hour, mode="synthetic"):
    entries = {e["id"]: e for e in read_json(CATALOG)["entries"]}
    encoding = GameEncoding.from_catalog(read_json(CATALOG))
    glyphs = load_bdf()
    page = bytearray(8192)
    # These original fill routines paint a white background, then XOR the
    # black letter shapes. Their inclusive two-pixel endpoint convention
    # fills x106..133, one extra row beneath the eight-pixel upper glyphs.
    for top, bottom in ((9,17),(21,27)):
        for y in range(top,bottom+1):
            for x in range(106,134):
                address=(y&7)*1024+((y>>3)&7)*128+(y>>6)*40+x//7
                page[address] |= 1 << (x%7)

    def draw(pixels, left, top):
        for y, row in enumerate(pixels):
            for x, value in enumerate(row):
                if not value:
                    continue
                xx, yy = left+x, top+y
                if not (106 <= xx < 132 and 9 <= yy < 29):
                    raise ValueError("Clock pixel crosses its original interior")
                address = (yy&7)*1024+((yy>>3)&7)*128+(yy>>6)*40+xx//7
                page[address] ^= 1 << (xx%7)

    def hangul(character, x, y):
        draw([[(row>>bit)&1 for bit in range(7)] for row in hgr_rows(glyphs, character)], x, y)

    weekday = test_mode.text(entries[f"c.weekdays.{day:02d}"]["translation"], encoding, mode)
    if len(weekday) != 1:
        raise ValueError("Clock weekday must fit the verified single cell")
    hangul(weekday, 106, 9)
    meridiem = test_mode.text(entries[f"bitmap.d.{'am' if hour<12 else 'pm'}"]["translation"], encoding, mode)
    for i, character in enumerate(meridiem):
        hangul(character, 116+i*8, 9)
    original_d = (ROOT / "assets/po/D.bin").read_bytes()
    original_c = (ROOT / "assets/po/C.bin").read_bytes()
    x = 113
    for address in (0xD780, 0xD798):
        index = original_c[address-0xD200+hour]
        offset = original_d[index]+256*original_d[index+112]-0xB900
        width, height = original_d[offset:offset+2]
        stride = (width+6)//7
        draw([[(original_d[offset+2+y*stride+col//7]>>(col%7))&1 for col in range(width)]
              for y in range(height)], x, 21)
        x += width+1
    return bytes(page)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", required=True)
    test_mode.argument(parser)
    options = parser.parse_args()
    directory = test_mode.directory(options.mode) / "clock-probe"
    directory.mkdir(parents=True, exist_ok=True)
    n = read_json(BUILD / "maps/N-symbols.json")
    source = ('.setcpu "6502"\n.segment "CODE"\nPROBE_ENTRY:\n'
        '        sei\n        cld\n        lda CLOCK_INITIAL\n        beq SETUP\n        lda #$20\n        sta $C1\n        lda #$00\n        sta $C0\n'
        '        tay\n        ldx #$20\n        lda #$80\nCLEAR: sta ($C0),y\n        iny\n        bne CLEAR\n'
        '        inc $C1\n        dex\n        bne CLEAR\n'
        'SETUP: lda #$00\n        sta $68\n        sta $BE\n        sta $A2\n'
        '        lda #$27\n        sta $BF\n        lda #$06\n        sta $5F\n        lda #$01\n        sta $74\n'
        '        lda $C054\n        lda CLOCK_DAY\n        sta $12\n        lda CLOCK_HOUR\n        sta $13\n'
        '        lda CLOCK_INITIAL\n        beq UPDATE\n')
    for label in ("N_DRAW_CLOCK_WEEKDAY", "N_DRAW_CLOCK_HOUR", "N_DRAW_CLOCK_AM_PM"):
        source += f"        jsr ${n[label]:04X}\n"
    source += ("        jmp PROBE_DONE\nUPDATE: lda CLOCK_HOUR\n        beq MIDNIGHT\n        cmp #$0C\n        beq NOON\n"
               f"        jsr ${n['N_DRAW_CLOCK_WEEKDAY']:04X}\n        jmp HOUR\n"
               f"MIDNIGHT: jsr ${n['N_DRAW_CLOCK_AM_PM']:04X}\n        jsr ${n['N_DRAW_CLOCK_WEEKDAY']:04X}\n        jmp HOUR\n"
               f"NOON: jsr ${n['N_DRAW_CLOCK_AM_PM']:04X}\nHOUR: jsr ${n['N_DRAW_CLOCK_HOUR']:04X}\n"
               "PROBE_DONE: jmp PROBE_DONE\nCLOCK_DAY: .byte 0\nCLOCK_HOUR: .byte 0\nCLOCK_INITIAL: .byte 0\n")
    (directory / "clock.s").write_text(source)
    binary, symbols = assemble(directory / "clock.s", directory, "clock", 0x0800, 0x400)
    write_json(directory / "manifest.json", {"symbols": symbols, "binary_sha256": sha256(binary)})
    manifest = read_json(test_mode.directory(options.mode) / "manifest.json")
    process, session = launch(options.session, ROOT / manifest["image"], options.mode)
    try:
        point = session.bp(0x601C)
        session.call("go")
        session.stopped(0x601C)
        session.clear(point)
        point = session.bp(0x6000)
        session.call("go")
        session.call("keys", "\r")
        session.stopped(0x6000)
        session.clear(point)
        test_mode.bootstrap(session)
        session.guard("synthetic-clock-before", "N")
        session.lua("return dofile('tools/korean/clock_test.lua')")
        results = []
        # Clock fields have disjoint rectangles. Cover every value of each
        # independently, plus both meridiem states; no Cartesian claim needed.
        cases = [(0,hour) for hour in range(24)] + [(day,0) for day in range(1,7)] + [(0,0)]
        for day, hour in cases:
            start = session.call("korean_clock_start", day, hour)
            session.call("go")
            session.stopped(start["done"])
            result = session.call("korean_clock_finish")
            raw = (session.directory / (result["name"]+".hgr")).read_bytes()
            expected = reference(day,hour,options.mode)
            if bytes(value&127 for value in raw) != expected:
                (directory / "expected-mismatch.hgr").write_bytes(expected)
                raise ValueError("Native clock ink differs from independent font reference: " + result["name"])
            for name in ("A", "X", "Y", "SP", "P", "PC"):
                if result["restored_cpu"][name] != result["saved_cpu"][name]:
                    raise ValueError("Clock probe CPU caller not restored")
            result.update(reference_pixels_match=True, hgr_sha256=sha256(raw))
            results.append(result)
        session.guard("synthetic-clock-after", "N")
        session.exit()
        process.wait(timeout=10)
        if process.returncode != 0:
            raise ValueError("Owned clock MAME did not exit normally")
        if sha256((session.directory / "carmen-world.hdv").read_bytes()) != manifest["image_sha256"]:
            raise ValueError("RAM-only clock test changed its media")
        destination = test_mode.runtime(options.mode) / "native-clock"
        destination.mkdir(parents=True, exist_ok=True)
        artifacts = {}
        for path in sorted(session.directory.glob("clock-*.hgr")):
            shutil.copyfile(path, destination / path.name)
            artifacts[path.name] = sha256(path.read_bytes())
        write_json(test_mode.runtime(options.mode) / "native-clock.json", {"format": 1, "status": "pass", "session": options.session,
            **test_mode.identity(options.mode), "probe_binary_sha256": sha256(binary),
            "D": manifest["files"]["D"], "cases": results, "artifacts": artifacts,
            "checks": ["Every hour 0..23, including noon/midnight and both full two-syllable meridiem words",
                "All seven weekday values; separate field rectangles stay inside original clock",
                "All page ink matches independent BDF/unchanged Arabic-digit pixels; HGR phase bit excluded",
                "Original overlay, display page, borrowed RAM/stack and CPU restored; media unchanged"],
            "scope": "31 native clock field cases including sequential redraws and weekday wrap; full game screenshots/lifecycle recorded separately"})
        print("Native clock: all 24 hours and 7 weekdays match independent pixels; owned MAME exited", flush=True)
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except Exception:
                process.kill()
                process.wait(timeout=5)


if __name__ == "__main__":
    main()
