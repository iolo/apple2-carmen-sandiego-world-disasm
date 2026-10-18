"""Disk-booted synthetic text lifecycle, with exact font/state/media checks."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import time

from .common import BUILD, DOCS, ROOT, read_json, sha256, write_json
from .font_lifecycle import Session
from .verify_save import extract
from . import test_mode


class SyntheticSession(Session):
    def __init__(self, name, mode="synthetic"):
        super().__init__(name)
        test_mode.directory(mode)
        self.mode = mode
        self.checks = []

    def checkpoint(self, name):
        return super().checkpoint(name.replace("font-", "synthetic-").replace("synthetic-", self.mode + "-"))

    def guard(self, name, module=None):
        name = name.replace("font-", "synthetic-").replace("synthetic-", self.mode + "-")
        result = self.call("korean_synthetic_check", name, *([module] if module else []))
        self.checks.append(name)
        print(f"{self.name}/{name}: full resident bytes match, decoder error 0", flush=True)
        return result

    def row(self, direction):
        self.clear()
        key = self.bp("N_HANDLE_MENU_KEY")
        self.call("korean_release_keys")
        self.call("go")
        # A keyboard matrix needs to observe a released key between identical
        # arrows. Debugger stops can otherwise join two taps into one hold.
        before, deadline = self.call("status")["time"], time.monotonic()+5
        while self.call("status")["time"] < before+0.08:
            if time.monotonic() > deadline:
                raise TimeoutError("Menu did not advance through key-release interval")
            time.sleep(0.05)
        self.call("korean_press", ":X7", "→" if direction > 0 else "←")
        registers = self.stopped("N_HANDLE_MENU_KEY")
        if registers["A"] & 0x7F != (0x15 if direction > 0 else 0x08):
            raise ValueError("Physical arrow did not produce the native menu code")
        self.call("korean_release_keys")
        self.clear(key)
        self.current = self.bp("N_WAIT_MENU_SELECTION")
        self.call("go")
        self.stopped("N_WAIT_MENU_SELECTION")

    def boot(self, detective, restore=False, expected_case=None):
        self.call("status")
        initial = self.bp(0x601C)
        self.call("go")
        self.stopped(0x601C)
        test_mode.bootstrap(self)
        self.guard("synthetic-r-initialized")
        self.clear(initial)
        r = read_json(BUILD / "maps/R-symbols.json")
        prompt = self.bp(r["R_SHOW_CASE_PROMPT"])
        self.call("go")
        self.stopped(r["R_SHOW_CASE_PROMPT"])
        self.clear(prompt)
        prompt = self.bp(r["R_WAIT_INPUT_TICKS"])
        self.call("go")
        self.stopped(r["R_WAIT_INPUT_TICKS"])
        self.guard("synthetic-r-announcement")
        self.clear(prompt)
        title = self.bp(r["R_SHOW_TITLE_CREDITS"])
        self.call("go")
        self.stopped(r["R_SHOW_TITLE_CREDITS"])
        self.clear(title)
        title = self.bp(r["R_WAIT_INPUT_TICKS"])
        self.call("go")
        self.stopped(r["R_WAIT_INPUT_TICKS"])
        self.guard("synthetic-r-title")
        self.clear(title)
        entry = self.bp(0x6000)
        self.call("go")
        self.call("keys", "\r")
        self.stopped(0x6000)
        self.guard("synthetic-n-entry", "N")
        self.clear(entry)
        name = self.bp("N_READ_NAME_KEY")
        self.call("go")
        self.stopped("N_READ_NAME_KEY")
        self.guard("synthetic-name-prompt")
        self.clear(name)
        self.call("korean_fast_text", True)
        if not restore:
            denied = self.bp("N_REJECT_RESERVED_NAME")
            self.call("go")
            self.call("keys", "Rookie\r")
            self.stopped("N_REJECT_RESERVED_NAME")
            self.guard("synthetic-english-name-rejected")
            self.clear(denied)
            name = self.bp("N_READ_NAME_KEY")
            self.call("go")
            self.stopped("N_READ_NAME_KEY")
            self.clear(name)
        answer = self.bp("N_READ_YES_NO_RESPONSE")
        self.call("go")
        self.call("keys", detective + "\r")
        self.stopped("N_READ_YES_NO_RESPONSE")
        self.guard("synthetic-resume-prompt" if restore else "synthetic-create-record")
        self.clear(answer)
        self.current = self.bp("N_WAIT_CITY_INPUT")
        self.call("go")
        self.call("keys", "Y\r")
        self.stopped("N_WAIT_CITY_INPUT")
        self.call("korean_fast_text", False)
        result = self.guard("synthetic-restored-city" if restore else "synthetic-city")
        if expected_case is not None:
            expected = expected_case.copy()
            expected[26] = 2
            if result["case_state"] != expected:
                raise ValueError("Fresh restore does not match all 33 case bytes")
        return result

    def computer(self):
        self.row(1)
        self.enter_menu("N_SHOW_COMPUTER_SAVE_MENU")
        self.enter_menu("N_OPEN_COMPUTER")
        self.guard("synthetic-computer")
        for category in range(2):
            if category:
                self.row(1)
            self.clear()
            self.current = self.bp("N_WAIT_COMPUTER_SELECTION")
            self.call("go")
            self.call("keys", "\r")
            self.stopped("N_WAIT_COMPUTER_SELECTION")
            result = self.guard("synthetic-computer-trait-"+str(category))
            if result["case_state"][27+category] != 0:
                raise ValueError("Computer did not select the original first trait value")
        self.clear()
        self.current = self.bp("N_WAIT_CITY_INPUT")
        self.call("go")
        self.call("keys", "\x1b")
        self.stopped("N_WAIT_CITY_INPUT")
        self.guard("synthetic-computer-return")
        self.row(-1)  # Visit Interpol -> Investigate, ready for travel_next.

    def save(self):
        self.row(1)
        self.enter_menu("N_SHOW_COMPUTER_SAVE_MENU")
        self.row(1)
        self.clear()
        point = self.bp("N_READ_GAME_KEY")
        self.call("go")
        self.call("keys", "\r")
        self.stopped("N_READ_GAME_KEY")
        self.checkpoint("synthetic-save-prompt")
        self.clear(point)
        point = self.bp("N_SAVE_CURRENT_CASE")
        self.call("go")
        self.call("keys", "\r")
        self.stopped("N_SAVE_CURRENT_CASE")
        before = self.guard("synthetic-before-save")["case_state"]
        self.clear(point)
        self.current = self.bp("N_SHOW_IDENTIFY_PROMPT")
        self.call("go")
        self.stopped("N_SHOW_IDENTIFY_PROMPT")
        self.guard("synthetic-after-save")
        return before


def launch(name, image, mode="synthetic"):
    if Path(name).name != name or (BUILD / name).exists():
        raise ValueError("New safe MAME session directory required")
    process = subprocess.Popen([sys.executable, "-m", "tools.korean.mame", "--session", name, "--image", str(image)],
                               cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    session = SyntheticSession(name, mode)
    deadline = time.monotonic()+15
    while not (session.directory / "mailbox").is_dir():
        if process.poll() is not None or time.monotonic() > deadline:
            process.terminate()
            raise RuntimeError("Owned synthetic MAME did not initialize")
        time.sleep(0.05)
    return process, session


def saved_media(image, before, detective, manifest, restored_image=None):
    roster, cases = extract(image, "F"), extract(image, "H")
    slots = [i for i in range(13) if roster[i*19:i*19+16].rstrip(b"\xff") == detective.encode("ascii")]
    if len(slots) != 1:
        raise ValueError("Synthetic detective is not unique in saved F")
    slot = slots[0]
    if roster[slot*19+18] != 1 or cases[slot*256:(slot+1)*256] != bytes(before)+bytes(223):
        raise ValueError("Synthetic save does not match case/zero padding/resume flag")
    changed = []
    for name, record in manifest["files"].items():
        content = extract(image, name)
        if sha256(content) != record["sha256"]:
            changed.append(name)
        if restored_image and name != "F" and extract(restored_image, name) != content:
            raise ValueError("Fresh restore changed a non-roster file: " + name)
    if sorted(changed) != ["F", "H"]:
        raise ValueError("Synthetic save changed files other than F/H: " + str(changed))
    if restored_image:
        expected = bytearray(roster)
        expected[slot*19+18] = 0
        if extract(restored_image, "F") != bytes(expected):
            raise ValueError("Fresh restore changed more than the original F resume flag")
    return {"slot": slot, "detective": detective, "case_state": before, "saved_resume_flag": 1,
            "restored_resume_flag": 0 if restored_image else None, "only_modified_files": changed,
            "saved_case_and_223_zero_bytes_match": True}


def archive(session):
    destination = test_mode.runtime(session.mode) / "synthetic-text" / session.name
    destination.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for path in sorted([*session.directory.glob(session.mode + "-*.json"), *session.directory.glob(session.mode + "-*.png"), session.directory / "session.json"]):
        shutil.copyfile(path, destination / path.name)
        hashes[path.name] = sha256(path.read_bytes())
    for name in ("F", "H"):
        data = extract(session.directory / "carmen-world.hdv", name)
        (destination / f"saved-{name}.bin").write_bytes(data)
        hashes[f"saved-{name}.bin"] = sha256(data)
    return {"session": session.name, "checks": session.checks, "artifacts": hashes,
            "image_sha256_after_session": sha256((session.directory / "carmen-world.hdv").read_bytes())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", required=True)
    parser.add_argument("--fresh-session", required=True)
    parser.add_argument("--name", default="SYNTHK2")
    test_mode.argument(parser)
    options = parser.parse_args()
    manifest = read_json(test_mode.directory(options.mode) / "manifest.json")
    image = ROOT / manifest["image"]
    if sha256(image.read_bytes()) != manifest["image_sha256"]:
        raise ValueError("Synthetic disk differs from its build manifest")
    owned = []
    try:
        process, initial = launch(options.session, image, options.mode)
        owned.append(process)
        initial.boot(options.name)
        initial.investigate()
        initial.computer()
        initial.travel_next()
        before = initial.save()
        initial.exit()
        process.wait(timeout=10)
        if process.returncode != 0:
            raise ValueError("Initial owned MAME did not exit normally")
        process, fresh = launch(options.fresh_session, initial.directory / "carmen-world.hdv", options.mode)
        owned.append(process)
        restored = fresh.boot(options.name, restore=True, expected_case=before)
        fresh.exit()
        process.wait(timeout=10)
        if process.returncode != 0:
            raise ValueError("Fresh owned MAME did not exit normally")
        save = saved_media(initial.directory / "carmen-world.hdv", before, options.name, manifest, fresh.directory / "carmen-world.hdv")
        report = {"format": 1, "status": "pass", **test_mode.identity(options.mode),
                  "catalog_sha256": manifest["catalog_sha256"], "save": save,
                  "fresh_restored_case": restored["case_state"], "sessions": [archive(initial), archive(fresh)],
                  "checks": [f"Disk-booted native font installation and full-size {options.mode} C/I/K/S2/N/R",
                      "Intro announcement/title with captions, complete N overlay identity before execution, English name rejection and registration",
                      "Computer captions, original English Escape input and two translated trait selections preserve native state",
                      "Investigation increments native count; travel reaches the actual planned route city",
                      "Font banks, resident C, I/K text, copy helper and immutable decoder instructions match at every checkpoint",
                      f"Save writes exactly captured case plus zero padding; only F/H differ from {options.mode} baseline",
                      "Fresh process restores all 33 case bytes except original menu reset at offset 26; clears only F resume flag"],
                  "scope": f"Full-size {options.mode} text/caption lifecycle; all dynamic-message layouts and exhaustive branch coverage remain open"}
        write_json(test_mode.runtime(options.mode) / "synthetic-text.json", report)
        print(f"{options.mode.title()} text save/fresh-boot lifecycle passed; owned MAME sessions exited", flush=True)
    finally:
        for process in owned:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)


if __name__ == "__main__":
    main()
