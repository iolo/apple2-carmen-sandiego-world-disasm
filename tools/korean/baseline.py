"""Record real English regression command results, without changing originals.

Run from the repository root: python3 -m tools.korean.baseline
"""

import subprocess

from .common import BUILD, DOCS, ROOT, original_inputs, sha256, write_json


def main():
    identities = original_inputs()
    BUILD.mkdir(parents=True, exist_ok=True)
    results = []
    for target in ("check", "test", "smoke"):
        result = subprocess.run(["make", target], cwd=ROOT, capture_output=True, text=True)
        output = result.stdout + result.stderr
        (BUILD / f"english-{target}.log").write_text(output)
        results.append({"command": ["make", target], "exit_code": result.returncode,
                        "output": output})
        print(output, end="", flush=True)
        if result.returncode:
            break
    report = {"format": 1, "original_inputs": identities, "commands": results,
              "rebuilt_po_sha256": sha256((ROOT / "build/carmen-world.po").read_bytes()),
              "limits": ["smoke covers the floppy pair; 800K gameplay needs runtime evidence",
                         "disk allocation and unused blocks may differ from originals"]}
    original_inputs()
    write_json(DOCS / "english-baseline.json", report)
    if len(results) != 3 or any(r["exit_code"] for r in results):
        raise SystemExit("English baseline failed; see docs/korean/english-baseline.json")


if __name__ == "__main__":
    main()
