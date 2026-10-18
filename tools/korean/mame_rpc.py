"""Call an owned MAME Lua mailbox, including while its debugger is stopped.

Examples:
  python3 -m tools.korean.mame_rpc --session demo --call status
  python3 -m tools.korean.mame_rpc --session demo --call read --args '[24576,16]'
  python3 -m tools.korean.mame_rpc --session demo --lua 'return a2.registers()'
"""

import argparse
import json
import os
from pathlib import Path
import time
import uuid

from .common import BUILD, read_json, write_json


def request(session, *, operation=None, args=None, code=None, timeout=10):
    directory = session / "mailbox"
    if not directory.is_dir():
        raise ValueError("Session has no mailbox; launch with the updated tools.korean.mame")
    deadline = time.monotonic() + timeout
    ready = directory / "ready.json"
    while not ready.exists():
        if time.monotonic() >= deadline:
            raise TimeoutError("MAME mailbox did not become ready")
        time.sleep(0.05)
    if not read_json(ready).get("ok"):
        raise ValueError(f"Mailbox startup failed: {read_json(ready)}")
    identifier = uuid.uuid4().hex
    value = {"id": identifier}
    if operation is not None:
        value.update(operation=operation, args=[] if args is None else args)
    else:
        value["code"] = code
    pending = directory / "request.json"
    lock = directory / "client.lock"
    # Single-flight transport. Never overwrite a request after a timeout: it
    # may still execute, so the caller must inspect its ID and archived receipt.
    try:
        handle = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError as error:
        raise ValueError("Another mailbox client owns this session") from error
    try:
        os.close(handle)
        if pending.exists():
            raise ValueError("An earlier request is pending; inspect it before sending another")
        unanswered = [p.name for p in directory.glob("*.request.json")
                      if not p.with_name(p.name.replace(".request.json", ".response.json")).exists()]
        if unanswered:
            raise ValueError(f"An accepted request has no receipt yet: {unanswered[0]}")
        temporary = directory / f"{identifier}.tmp"
        write_json(temporary, value)
        os.replace(temporary, pending)
        response_path = directory / f"{identifier}.response.json"
        while not response_path.exists():
            if time.monotonic() >= deadline:
                raise TimeoutError(f"No completion receipt for {identifier}; do not automatically retry a mutation")
            time.sleep(0.05)
        response = read_json(response_path)
        if response.get("id") != identifier:
            raise ValueError("Mismatched mailbox receipt")
        return response
    finally:
        lock.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", required=True, help="directory name below build/korean")
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--call", dest="operation", help="a2 helper name")
    action.add_argument("--lua", dest="code", help="Lua source; return a JSON-compatible value")
    parser.add_argument("--args", default="[]", help="JSON positional arguments for --call")
    parser.add_argument("--timeout", type=float, default=10)
    options = parser.parse_args()
    if Path(options.session).name != options.session or not 0 < options.timeout <= 60:
        parser.error("safe session name and timeout in (0,60] required")
    args = json.loads(options.args)
    if not isinstance(args, list):
        parser.error("--args must be a JSON array")
    response = request(BUILD / options.session, operation=options.operation,
                       args=args, code=options.code, timeout=options.timeout)
    print(json.dumps(response, ensure_ascii=False))
    if not response.get("ok"):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
