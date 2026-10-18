"""Verify N/R pixels and the native narrow typewriter's complete glyph stream."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import time

from .common import BUILD, DOCS, ROOT, read_json, sha256, write_json
from .mame_rpc import request
from .render_probe import build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", required=True)
    options = parser.parse_args()
    if Path(options.session).name != options.session or (BUILD / options.session).exists():
        parser.error("new safe session name required")
    fixture = build()
    directory = BUILD / options.session
    process = subprocess.Popen([sys.executable, "-m", "tools.korean.mame", "--session", options.session],
                               cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 15
        while not (directory / "mailbox").is_dir():
            if process.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError("MAME did not initialize")
            time.sleep(0.05)

        def call(operation, *args):
            result = request(directory, operation=operation, args=list(args))
            if not result["ok"]:
                raise ValueError(result)
            return result.get("result")

        def stopped(address):
            deadline = time.monotonic() + 15
            while call("status")["debugger"] != "stop":
                if time.monotonic() >= deadline:
                    raise TimeoutError("Renderer probe did not complete")
                time.sleep(0.05)
            if call("registers")["PC"] != address:
                raise ValueError("Unexpected renderer stop")

        point = call("breakpoint", 0x601C)["id"]
        call("go")
        stopped(0x601C)
        call("clear_breakpoint", point)
        loaded = request(directory, code="dofile('tools/korean/native_probe.lua'); return {loaded=true}")
        if not loaded["ok"]:
            raise ValueError(loaded)
        results = []
        for tag in ("R", "N", "TW"):
            start = call("korean_renderer_start", tag)
            call("go")
            stopped(start["initialized"])
            installed = call("korean_renderer_install")
            if tag == "TW":
                call("korean_fast_text", True)
            call("go")
            stopped(installed["done"])
            call("korean_fast_text", False)
            present = call("korean_renderer_present")
            deadline = time.monotonic() + 5
            while call("status")["time"] < present["time_before"] + 0.04:
                if time.monotonic() >= deadline:
                    raise TimeoutError("Completed renderer frame did not advance")
                time.sleep(0.05)
            call("pause")
            stop = call("korean_renderer_stop")
            stopped(stop["done"])
            result = call("korean_renderer_finish")
            if result["body_pointer"] != fixture["body_terminator"]:
                raise ValueError("Renderer did not consume exactly to the body NUL")
            if tag == "TW":
                if result["glyph_trace"] != fixture["typewriter_trace"]:
                    raise ValueError("Typewriter lost, repeated or changed a glyph")
                if result["body_cursor"] != {"column": 3, "bit": 3, "row": 153}:
                    raise ValueError("Typewriter did not restore its native cursor")
            else:
                if not result["reference_pixels_match"]:
                    raise ValueError("Native renderer pixels differ from independent font reference")
                expected = {"column": fixture["body_end_x"] // 7, "bit": fixture["body_end_x"] % 7,
                            "row": fixture["body_end_row"]}
                if result["body_cursor"] != expected:
                    raise ValueError("Native renderer cursor disagrees with layout model")
                if (directory / f"renderer-{tag}.hgr").read_bytes() != (BUILD / "render-probe/expected.hgr").read_bytes():
                    raise ValueError("HGR artifact does not match the asserted pixel reference")
            for name in ("A", "X", "Y", "SP", "P", "PC"):
                if result["cpu_restored"][name] != result["saved_cpu"][name]:
                    raise ValueError("Caller CPU state not restored")
            results.append(result)
            print(f"{tag}: {'complete glyph trace' if tag == 'TW' else 'all 8192 HGR bytes'} match", flush=True)
        call("exit")
        process.wait(timeout=10)
        if process.returncode != 0:
            raise ValueError("Owned MAME exit failed")
        profile = read_json(directory / "session.json")
        if sha256((directory / "carmen-world.hdv").read_bytes()) != profile["image_sha256"]:
            raise ValueError("RAM-only renderer probe changed media")
        destination = DOCS / "runtime/native-renderers"
        destination.mkdir(parents=True, exist_ok=True)
        artifacts = {}
        for path in sorted(directory.glob("renderer-*")):
            shutil.copyfile(path, destination / path.name)
            artifacts[path.name] = sha256(path.read_bytes())
        report = {"format": 1, "status": "pass", "session": options.session, "profile": profile,
                  "library": read_json(BUILD / "library/manifest.json"),
                  "renderers": read_json(BUILD / "renderers/manifest.json"),
                  "fixture": fixture, "probes": results, "artifacts": artifacts,
                  "checks": ["N and R mixed-script raster matches independent pixel reference byte-for-byte",
                      "Native controls 80/81/82, forced 8D break, centered width and NUL termination",
                      "Lead at A0FF and trail at A100; IDs above 255 and bank split above 511",
                      "Unspaced ASCII and Hangul words wrap at a complete glyph boundary",
                      "Typewriter drawing-call data trace matches every expected glyph; measurement calls excluded by stack return address",
                      "Typewriter retains native leading-80 marker and indentation semantics",
                      "CPU, C data, banks, both borrowed HGR pages restored; disk unchanged"],
                  "scope": "Synthetic RAM probes of text measurement/drawing; full synthetic game/bitmap integration remains required"}
        write_json(DOCS / "runtime/native-renderers.json", report)
        print("Native renderer tests archived; owned MAME exited")
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


if __name__ == "__main__":
    main()
