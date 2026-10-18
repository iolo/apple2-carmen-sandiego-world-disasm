"""Audit full-font candidate RAM through an English save and fresh restore.

Attach to a newly launched, owned mailbox session stopped at reset. Its input
disk must contain the named detective and a resumable case. This experiment
does not install translated strings or the multibyte renderer.
"""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import time

from .common import BUILD, DOCS, ROOT, read_json, sha256, write_json
from .mame_rpc import request
from .verify_save import verify


class Session:
    def __init__(self, name):
        self.name = name
        self.directory = BUILD / name
        self.symbols = read_json(BUILD / "maps/N-symbols.json")
        self.guards = []
        self.current = None

    def call(self, operation, *args):
        receipt = request(self.directory, operation=operation, args=list(args))
        if not receipt["ok"]:
            raise RuntimeError(receipt)
        return receipt.get("result")

    def lua(self, code):
        receipt = request(self.directory, code=code)
        if not receipt["ok"]:
            raise RuntimeError(receipt)
        return receipt.get("result")

    def bp(self, label):
        address = self.symbols[label] if isinstance(label, str) else label
        return self.call("breakpoint", address)["id"]

    def clear(self, identifier=None):
        if identifier is None:
            identifier, self.current = self.current, None
        self.call("clear_breakpoint", identifier)

    def stopped(self, label, timeout=20):
        address = self.symbols[label] if isinstance(label, str) else label
        deadline = time.monotonic() + timeout
        while self.call("status")["debugger"] != "stop":
            if time.monotonic() >= deadline:
                raise TimeoutError(f"{self.name}: did not stop at {label}")
            time.sleep(0.05)
        registers = self.call("registers")
        if registers["PC"] != address:
            raise ValueError(f"Wrong stop for {label}: {registers}")
        return registers

    def checkpoint(self, name):
        return self.call("korean_checkpoint", name)

    def guard(self, name):
        result = self.call("korean_font_guard_check", name)
        if (result["unexpected_accesses"] or result["recent_self_test_hits"] != 8
                or not all(r["identical"] for r in result["regions"])):
            raise ValueError(f"Font residency check failed: {result}")
        self.guards.append(name)
        print(f"{self.name}/{name}: intact, CPU accesses 0, debugger accesses {result['debugger_accesses']}", flush=True)
        return result

    def boot_restore(self, detective, expected_case=None):
        self.call("status")  # Fresh request, not stale ready-file evidence.
        initial = self.bp(0x601C)
        self.call("go")
        self.stopped(0x601C)
        self.lua("dofile('tools/korean/font_guard.lua'); return a2.korean_font_guard_start()")
        self.guard("font-installed")
        self.clear(initial)
        entry = self.bp(0x6000)
        self.call("go")
        deadline, last_key = time.monotonic() + 20, -1000
        while True:
            status = self.call("status")
            if status["debugger"] == "stop":
                break
            if status["time"] >= 100 and status["time"] - last_key >= 100:
                self.call("keys", "\r")
                last_key = status["time"]
            if time.monotonic() > deadline:
                raise TimeoutError("Intro did not reach N")
            time.sleep(0.05)
        self.stopped(0x6000)
        self.guard("font-n-entry")
        self.call("korean_font_guard_survey", "font-n-entry")
        captured = (self.directory / "font-n-entry-main.bin").read_bytes()
        original = (ROOT / "assets/po/N.bin").read_bytes()
        if captured[0x6000 - 0x200:0x6000 - 0x200 + len(original)] != original:
            raise ValueError("N entry is not the complete original module")
        self.clear(entry)
        name = self.bp("N_READ_NAME_KEY")
        self.call("go")
        self.stopped("N_READ_NAME_KEY")
        prompt = self.bp("N_READ_YES_NO_RESPONSE")
        self.call("korean_fast_text", True)
        self.clear(name)
        self.call("go")
        self.call("keys", detective + "\r")
        self.stopped("N_READ_YES_NO_RESPONSE")
        self.checkpoint("font-resume-prompt")
        self.call("korean_fast_text", False)
        self.clear(prompt)
        self.current = self.bp("N_WAIT_CITY_INPUT")
        self.call("go")
        self.call("keys", "Y\r")
        self.stopped("N_WAIT_CITY_INPUT")
        self.guard("font-restored-city")
        result = self.checkpoint("font-restored-city")
        if expected_case is not None:
            expected = expected_case.copy()
            expected[26] = 2
            if result["case_state"] != expected:
                raise ValueError("Fresh restore does not match all 33 case bytes")
        return result

    def row(self, direction):
        self.clear()
        key = self.bp("N_HANDLE_MENU_KEY")
        self.call("go")
        self.call("korean_press", ":X7", "→" if direction > 0 else "←")
        registers = self.stopped("N_HANDLE_MENU_KEY")
        if registers["A"] & 0x7F != (0x15 if direction > 0 else 0x08):
            raise ValueError("Physical arrow did not produce the native menu code")
        self.call("korean_release_keys")
        self.clear(key)
        self.current = self.bp("N_WAIT_MENU_SELECTION")
        self.call("go")
        self.stopped("N_WAIT_MENU_SELECTION")

    def enter_menu(self, entry):
        self.clear()
        point = self.bp(entry)
        self.call("go")
        self.call("keys", "\r")
        self.stopped(entry)
        self.clear(point)
        self.current = self.bp("N_WAIT_MENU_SELECTION")
        self.call("go")
        self.stopped("N_WAIT_MENU_SELECTION")

    def investigate(self):
        before = self.checkpoint("font-before-investigation")["case_state"]
        self.enter_menu("N_SHOW_INVESTIGATION_MENU")
        self.clear()
        self.current = self.bp("N_WAIT_CITY_INPUT")
        self.call("go")
        self.call("keys", "\r")
        self.stopped("N_WAIT_CITY_INPUT")
        after = self.checkpoint("font-investigation")["case_state"]
        if after[22] != (before[22] + 1) & 255:
            raise ValueError("Investigation did not increment its native count")
        self.guard("font-investigation")

    def travel_next(self):
        before = self.checkpoint("font-before-travel")["case_state"]
        target = before[3 + before[2]]
        self.row(-1)  # Main Investigate -> Depart by Plane.
        self.enter_menu("N_SHOW_TRAVEL_MENU")
        state = self.checkpoint("font-destinations")
        page = self.call("read", 0x9F00, 256)["bytes"]
        start, end = page[216 + before[17]:218 + before[17]]
        choices = page[start:end]
        if target not in choices:
            raise ValueError("Planned route is not in the native destination list")
        wanted, selected = choices.index(target), state["menu_state"][8]
        while selected != wanted:
            forwards = (wanted - selected) % len(choices)
            backwards = (selected - wanted) % len(choices)
            direction = 1 if forwards <= backwards else -1
            self.row(direction)
            selected = (selected + direction) % len(choices)
        self.clear()
        self.current = self.bp("N_WAIT_CITY_INPUT")
        self.call("go")
        self.call("keys", "\r")
        self.stopped("N_WAIT_CITY_INPUT")
        after = self.checkpoint("font-travel")["case_state"]
        if after[17] != target or after[17] == before[17]:
            raise ValueError("Travel did not reach the planned destination")
        self.guard("font-travel")

    def save(self):
        self.row(1)  # Main Investigate -> Visit Interpol.
        self.enter_menu("N_SHOW_COMPUTER_SAVE_MENU")
        self.row(1)  # Use Computer -> Save Case.
        self.clear()
        point = self.bp("N_READ_GAME_KEY")
        self.call("go")
        self.call("keys", "\r")
        self.stopped("N_READ_GAME_KEY")
        self.checkpoint("font-save-prompt")
        self.clear(point)
        point = self.bp("N_SAVE_CURRENT_CASE")
        self.call("go")
        self.call("keys", "\r")
        self.stopped("N_SAVE_CURRENT_CASE")
        before = self.checkpoint("font-before-save")["case_state"]
        self.guard("font-before-save")
        self.clear(point)
        self.current = self.bp("N_SHOW_IDENTIFY_PROMPT")
        self.call("go")
        self.stopped("N_SHOW_IDENTIFY_PROMPT")
        self.guard("font-after-save")
        self.checkpoint("font-after-save")
        self.call("korean_font_guard_survey", "font-after-save")
        return before

    def exit(self):
        self.call("korean_release_keys")
        self.call("korean_fast_text", False)
        self.call("exit")
        pid = read_json(self.directory / "session.json")["pid"]
        deadline = time.monotonic() + 10
        while Path(f"/proc/{pid}/cmdline").exists():
            # A zombie has no cmdline and is terminal even before its shell reaps it.
            if not Path(f"/proc/{pid}/cmdline").read_bytes():
                break
            if time.monotonic() > deadline:
                raise TimeoutError("Owned mailbox session did not exit")
            time.sleep(0.05)


def archive(session):
    destination = DOCS / "runtime/font-residency" / session.name
    destination.mkdir(parents=True, exist_ok=True)
    paths = set()
    for name in session.guards:
        paths.update(session.directory.glob(name + "-*.bin"))
        paths.add(session.directory / (name + "-font-guard.json"))
    paths.update(session.directory.glob("font-*.png"))
    paths.update(session.directory.glob("font-*.json"))
    paths.add(session.directory / "session.json")
    hashes = {}
    for path in sorted(paths):
        shutil.copyfile(path, destination / path.name)
        hashes[path.name] = sha256(path.read_bytes())
    return {"session": session.name, "guards": session.guards, "artifacts": hashes}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", required=True)
    parser.add_argument("--fresh-session", required=True)
    parser.add_argument("--name", default="MAMEFONT")
    parser.add_argument("--expected-before", type=Path, required=True)
    options = parser.parse_args()
    for name in (options.session, options.fresh_session):
        if Path(name).name != name:
            parser.error("safe session directory names required")
    first = Session(options.session)
    source_case = read_json(options.expected_before)["case_state"]
    first.boot_restore(options.name, source_case)
    first.investigate()
    first.travel_next()
    saved = first.save()
    first.exit()
    # verify() also checks the original file hashes and only F/H differences.
    verify(first.directory / "carmen-world.hdv", first.directory / "font-before-save.json", options.name)
    if (BUILD / options.fresh_session).exists():
        raise ValueError("Fresh session directory already exists")
    process = subprocess.Popen([sys.executable, "-m", "tools.korean.mame", "--session", options.fresh_session,
                               "--image", str(first.directory / "carmen-world.hdv")],
                              cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + 15
    while not (BUILD / options.fresh_session / "mailbox").is_dir():
        if process.poll() is not None or time.monotonic() > deadline:
            raise RuntimeError("Fresh MAME process failed to start")
        time.sleep(0.05)
    fresh = Session(options.fresh_session)
    fresh.boot_restore(options.name, saved)
    fresh.exit()
    process.wait(timeout=10)
    save = verify(first.directory / "carmen-world.hdv", first.directory / "font-before-save.json", options.name,
                  fresh.directory / "font-restored-city.json", fresh.directory / "carmen-world.hdv")
    report = {"format": 1, "status": "pass", "catalog_sha256": read_json(DOCS / "encoding-roundtrip.json")["catalog_sha256"],
              "font_bytes": len((BUILD / "draft-fixtures/KF.bin").read_bytes()),
              "font_sha256": sha256((BUILD / "draft-fixtures/KF.bin").read_bytes()),
              "sessions": [archive(first), archive(fresh)], "save_restore": save,
              "debugger_filter": "machine:side_effects_disabled() accesses counted separately; all 8 taps retested at every checkpoint",
              "scope": "Full font and code/helper canaries in original English lifecycle; Korean renderer and synthetic text integration still required"}
    write_json(DOCS / "runtime/font-residency.json", report)
    print("Full-font residency lifecycle passed; both owned sessions exited", flush=True)


if __name__ == "__main__":
    main()
