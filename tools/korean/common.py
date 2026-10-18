"""Shared paths and deterministic serialization for Korean edition evidence."""

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets/korean"
DOCS = ROOT / "docs/korean"
BUILD = ROOT / "build/korean"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def original_inputs():
    """Verify original media and every extracted file before taking evidence."""
    manifest = read_json(ROOT / "reconstruction/manifest.json")
    identities = {}
    for variant, image in manifest["images"].items():
        paths = {image["input"]: image["sha256"]}
        paths.update({file["asset"]: file["sha256"] for file in image["files"].values()})
        for name, expected in paths.items():
            actual = sha256((ROOT / name).read_bytes())
            if actual != expected:
                raise ValueError(f"Original input changed: {name}: {actual} != {expected}")
        identities[variant] = {"path": image["input"], "sha256": image["sha256"],
                               "verified_extracted_files": len(image["files"])}
    return {"manifest_sha256": sha256((ROOT / "reconstruction/manifest.json").read_bytes()),
            "images": identities}
