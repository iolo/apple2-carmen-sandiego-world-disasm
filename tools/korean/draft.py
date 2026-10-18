"""Apply UTF-8 draft translations and audit coverage before human review.

The catalog is authoritative. Batch JSON is an editing input, not a second
build source. This command never creates approval or patches game media.
"""

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import unicodedata

from .catalog import CATALOG, CONTROL_RE, roundtrip
from .common import DOCS, read_json, sha256, write_json


def audit(catalog, complete=False, persist=True):
    roundtrip(catalog)
    entries = [e for e in catalog["entries"] if e["translatable"]]
    missing = [e["id"] for e in entries if e["translation"] is None]
    errors, glyphs = [], set()
    for entry in entries:
        text = entry["translation"]
        if text is None:
            continue
        if unicodedata.normalize("NFC", text) != text:
            errors.append(f"{entry['id']}: draft is not NFC")
        if any(unicodedata.category(c) in ("Cc", "Cf") and
               not (c == "\n" and entry["codec"] == "bitmap") for c in text):
            errors.append(f"{entry['id']}: literal control character")
        expected = Counter(p["token"] for p in entry["protected_tokens"] if p["token"].startswith("<CTRL:"))
        actual = Counter(m[0] for m in CONTROL_RE.finditer(text))
        if actual != expected:
            errors.append(f"{entry['id']}: protected renderer controls changed")
        if re.search(r"<ctrl", CONTROL_RE.sub("", text), re.IGNORECASE):
            errors.append(f"{entry['id']}: malformed renderer control notation")
        if entry.get("pronoun_substitution"):
            if any(text.count(p) != entry["original"].count(p) for p in "#@^"):
                errors.append(f"{entry['id']}: pronoun markers changed")
        for token in entry.get("input_tokens", []):
            if token["display"] not in text:
                errors.append(f"{entry['id']}: input hint {token['display']} is missing")
        visible = CONTROL_RE.sub("", text)
        if entry.get("pronoun_substitution"):
            visible = re.sub(r"[#@^]", "", visible)
        glyphs.update(c for c in visible if c != "\n")
    report = {"format": 1, "catalog_sha256": sha256((json.dumps(catalog, ensure_ascii=False, indent=2) + "\n").encode("utf-8")),
              "translation_targets": len(entries), "draft_entries": len(entries) - len(missing),
              "untranslated_ids": missing, "errors": errors, "complete_draft": not missing and not errors,
              "unicode_characters": "".join(sorted(glyphs)), "unique_characters": len(glyphs),
              "unique_hangul_syllables": sum(0xAC00 <= ord(c) <= 0xD7A3 for c in glyphs),
              "status": "draft only; full-size encoding, layout and runtime capacity remain required before review"}
    if persist:
        write_json(DOCS / "draft-status.json", report)
    if errors or (complete and missing):
        raise ValueError("Draft audit failed: " + "; ".join(errors[:10]) +
                         (f"; {len(missing)} untranslated targets" if complete and missing else ""))
    return report


def apply(catalog, batch):
    entries = {entry["id"]: entry for entry in catalog["entries"]}
    changed = []
    for identifier, translation in batch.items():
        if identifier not in entries or not entries[identifier]["translatable"]:
            raise ValueError(f"Unknown or excluded translation ID: {identifier}")
        if not isinstance(translation, str):
            raise ValueError(f"Translation must be text: {identifier}")
        translation = unicodedata.normalize("NFC", translation)
        entry = entries[identifier]
        if entry["translation"] != translation:
            entry["translation"] = translation
            entry["status"] = "draft"
            changed.append(identifier)
    if changed:
        catalog["approval"] = None
        for entry in catalog["entries"]:
            if entry["translatable"] and entry["translation"] is not None:
                entry["status"] = "draft"
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", type=Path, help="JSON object mapping stable IDs to draft Korean text")
    parser.add_argument("--complete", action="store_true", help="fail unless every target has a valid draft")
    args = parser.parse_args()
    catalog = read_json(CATALOG)
    if args.apply:
        changed = apply(catalog, read_json(args.apply))
        # Validate before persisting, including protected English references.
        audit(catalog, persist=False)
        write_json(CATALOG, catalog)
        print(f"Updated {len(changed)} draft entries; approval remains unset")
    report = audit(catalog, args.complete)
    print(f"Draft coverage: {report['draft_entries']}/{report['translation_targets']}; "
          f"{report['unique_hangul_syllables']} Hangul syllables so far")


if __name__ == "__main__":
    main()
