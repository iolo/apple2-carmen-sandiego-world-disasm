"""Exercise the real MAME mailbox at startup, a breakpoint and after Lua errors."""

import argparse
from pathlib import Path
import subprocess
import sys
import time

from .common import BUILD, DOCS, ROOT, read_json, sha256, write_json
from .mame_rpc import request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", required=True, help="new owned session directory name")
    args = parser.parse_args()
    if Path(args.session).name != args.session:
        parser.error("safe session name required")
    session = BUILD / args.session
    if session.exists():
        parser.error("session directory must be new")
    process = subprocess.Popen([sys.executable, "-m", "tools.korean.mame", "--session", args.session],
                               cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    receipts = []
    try:
        deadline = time.monotonic() + 15
        while not (session / "mailbox").is_dir():
            if process.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError("MAME launcher failed before mailbox creation")
            time.sleep(0.05)

        def call(operation=None, args=None, code=None, success=True):
            receipt = request(session, operation=operation, args=args, code=code, timeout=10)
            receipts.append(receipt)
            if receipt["ok"] != success:
                raise AssertionError(receipt)
            return receipt.get("result")

        initial = call("status")
        assert initial["debugger"] == "stop"
        assert call(code="return 6 * 7") == 42
        initial_registers = call("registers")
        assert isinstance(initial_registers["PC"], int)
        breakpoint = call("breakpoint", [0x601C])["id"]
        call("go")
        deadline = time.monotonic() + 10
        while call("status")["debugger"] != "stop":
            if time.monotonic() > deadline:
                raise TimeoutError("R initialization breakpoint did not stop")
            time.sleep(0.05)
        assert call("registers")["PC"] == 0x601C
        call(code="error('intentional mailbox smoke error')", success=False)
        call(code="return )", success=False)
        assert call("status")["debugger"] == "stop"
        call("pause")
        assert call("status")["paused"]
        screenshot = session / "mailbox-proof.png"
        call("screenshot", [str(screenshot)])
        assert screenshot.read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
        call("clear_breakpoint", [breakpoint])
        call("exit")
        process.wait(timeout=10)
        assert process.returncode == 0
        sources = ("mame.py", "mame_rpc.py", "mailbox_smoke.py", "mame_plugins/carmen_mailbox/init.lua",
                   "mame_plugins/carmen_mailbox/plugin.json")
        report = {"format": 1, "status": "pass", "session": args.session,
                  "profile": read_json(session / "session.json"),
                  "ready": read_json(session / "mailbox/ready.json"),
                  "transport": "workspace JSON files; no stdin, terminal or network control",
                  "checks": ["automatic startup while debugger stopped", "arbitrary Lua return value",
                      "register read", "breakpoint creation and actual stop at R initialization",
                      "runtime and syntax errors produce receipts without disabling the transport",
                      "ordinary pause", "screenshot", "owned exit without a console wakeup"],
                  "sources": {name: sha256((ROOT / "tools/korean" / name).read_bytes()) for name in sources},
                  "receipts": receipts, "screenshot_sha256": sha256(screenshot.read_bytes()),
                  "exit_code": process.returncode}
        write_json(DOCS / "runtime/mame-mailbox.json", report)
        print(f"MAME mailbox smoke passed: {len(receipts)} matching receipts; owned process exited")
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
