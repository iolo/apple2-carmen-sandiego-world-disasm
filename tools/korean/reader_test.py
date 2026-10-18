"""Run complete-charset native reader tests without changing the game disk."""

import argparse

from . import test_mode
import shutil

from .common import BUILD, DOCS, ROOT, read_json, sha256, write_json
from .reader_probe import build
from .synthetic_test import launch


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", required=True)
    test_mode.argument(parser)
    options = parser.parse_args()
    fixture = build(options.mode)
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
        session.guard("synthetic-reader-before", "N")
        session.lua("return dofile('tools/korean/reader_probe.lua')")
        results = []
        for i, probe in enumerate(fixture["probes"], 1):
            started = session.call("korean_reader_start", i)
            session.call("go")
            session.stopped(started["done"])
            result = session.call("korean_reader_finish")
            output = (session.directory / f"reader-{probe['name']}-output.bin").read_bytes()
            if sha256(output) != probe["expected_sha256"]:
                raise ValueError("Native reader output differs from host expansion")
            for name in ("A", "X", "Y", "SP", "P", "PC"):
                if result["restored_cpu"][name] != result["saved_cpu"][name]:
                    raise ValueError("Reader probe did not restore CPU caller")
            session.guard("synthetic-reader-after-" + probe["name"].lower(), "N")
            results.append(result)
            print(probe["name"] + ": exact expanded bytes and source/cursor/tail match", flush=True)
        session.exit()
        process.wait(timeout=10)
        if process.returncode != 0:
            raise ValueError("Owned reader MAME did not exit normally")
        if sha256((session.directory / "carmen-world.hdv").read_bytes()) != manifest["image_sha256"]:
            raise ValueError("RAM-only reader test changed disposable game disk")
        destination = test_mode.runtime(options.mode) / "native-readers"
        destination.mkdir(parents=True, exist_ok=True)
        artifacts = {}
        for path in sorted([*session.directory.glob("reader-*"), *session.directory.glob(session.mode+"-reader-*.json")]):
            shutil.copyfile(path, destination / path.name)
            artifacts[path.name] = sha256(path.read_bytes())
        write_json(test_mode.runtime(options.mode) / "native-readers.json", {
            "format": 1, "status": "pass", "session": options.session,
            **test_mode.identity(options.mode), "fixture": fixture,
            "probes": results, "artifacts": artifacts,
            "checks": ["All 710 glyphs copied literally through N expansion and C's auxiliary K reader",
                "Female/male #/@/^ substitutions, including distinct female object UI 105",
                "Pronoun and literal appends cross output pages and source scans cross input pages",
                "Period, trailing quote and final multibyte glyph at $xxFF preserve exact NUL/cursor semantics",
                "Complete outputs match independent host expansion; remaining buffer canaries unchanged",
                "Borrowed RAM, stack, original overlay/resident data and CPU restored; media unchanged"],
            "scope": "Native reader and sentence-append edge cases; not all game branch/layout coverage"})
        print("Native C/N reader tests archived; owned MAME exited", flush=True)
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
