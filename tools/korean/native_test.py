"""Run and archive the real native all-glyph/ABI probes in a fresh MAME process."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import time

from .common import BUILD, DOCS, ROOT, read_json, sha256, write_json
from .library import build
from .mame_rpc import request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", required=True)
    options = parser.parse_args()
    if Path(options.session).name != options.session or (BUILD / options.session).exists():
        parser.error("new safe session directory name required")
    manifest = build()
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
                    raise TimeoutError("Native probe did not complete")
                time.sleep(0.05)
            if call("registers")["PC"] != address:
                raise ValueError("Unexpected native probe stop")

        point = call("breakpoint", 0x601C)["id"]
        call("go")
        stopped(0x601C)
        call("clear_breakpoint", point)
        loaded = request(directory, code="dofile('tools/korean/native_probe.lua'); return {loaded=true}")
        if not loaded["ok"]:
            raise ValueError(loaded)
        results = []
        expected_font = (BUILD / "draft-fixtures/KF.bin").read_bytes()
        for mode in ("C2", "C6"):
            start = call("korean_native_start", mode)
            call("go")
            stopped(start["done"])
            result = call("korean_native_finish")
            if (directory / f"native-{mode}-pixels.bin").read_bytes() != expected_font:
                raise ValueError("Complete native font pixels do not match the pinned source")
            for name in ("A", "X", "Y", "SP", "P", "PC"):
                if result["cpu_restored"][name] != result["saved_cpu"][name]:
                    raise ValueError("Original caller registers not restored")
            results.append(result)
        call("exit")
        process.wait(timeout=10)
        if process.returncode != 0:
            raise ValueError("Owned MAME exit failed")
        profile = read_json(directory / "session.json")
        if sha256((directory / "carmen-world.hdv").read_bytes()) != profile["image_sha256"]:
            raise ValueError("RAM-only probe changed disposable media")
        destination = DOCS / "runtime/native-font"
        destination.mkdir(parents=True, exist_ok=True)
        artifacts = {}
        for path in sorted(directory.glob("native-*")):
            shutil.copyfile(path, destination / path.name)
            artifacts[path.name] = sha256(path.read_bytes())
        report = {"format": 1, "status": "pass", "session": options.session,
                  "profile": profile, "library_sha256": manifest["sha256"],
                  "font_sha256": manifest["font_sha256"], "font_bytes": len(expected_font),
                  "glyphs_per_decoder": len(expected_font) // 8, "probes": results,
                  "probe_binaries": {mode: probe["sha256"] for mode, probe in manifest["probes"].items()},
                  "artifacts": artifacts,
                  "checks": ["Native boot installer replaces poisoned font RAM in both banks",
                      "All glyph IDs through both source pointers, including IDs above 255 and the bank split at 512",
                      "Lead/trail pairs cross source pages; final glyph immediately precedes NUL",
                      f"All {len(expected_font)} fetched pixel bytes match the pinned font",
                      "A/X/Y, alternating carry, set overflow/decimal and disabled-IRQ flags, cache dimensions and banks checked in native code",
                      "Source pointer stops on NUL, auxiliary tail and original C restored",
                      "CPU caller restored and disk image unchanged"],
                  "scope": "Shared native decoder/font library; N/R text hooks still require tests"}
        write_json(DOCS / "runtime/native-font.json", report)
        print("Native C2/C6 all-glyph probes passed and archived; owned MAME exited")
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
