"""Extract a location-stable UTF-8 catalog and verify original text byte ranges.

Original text/markup is kept independently of translation and approval state.
Repeated text keeps every release/location reference. Empty S2 fields survive.
Run: python3 -m tools.korean.catalog extract|check
"""

import argparse
from collections import Counter
import re
import sys

from .common import ASSETS, DOCS, ROOT, original_inputs, read_json, sha256, write_json

sys.path.insert(0, str(ROOT / "tools"))
from extract_assets import render_s2_line, s2_index
from s2_codec import c_dictionary, encode_line, markup_line


CONTROL_RE = re.compile(r"<CTRL:([0-9A-F]{2})>")
PRONOUNS = {"#": "subject: she/he", "@": "possessive: her/his", "^": "object: her/him"}
CATALOG = ASSETS / "catalog.json"


def visible_segments(segments):
    return "".join(segment["text"] if "text" in segment else
                   f"<CTRL:{segment['byte']:02X}>" for segment in segments)


def encode_controls(text):
    result = bytearray()
    cursor = 0
    for match in CONTROL_RE.finditer(text):
        result.extend(text[cursor:match.start()].encode("ascii"))
        result.append(int(match[1], 16))
        cursor = match.end()
    result.extend(text[cursor:].encode("ascii"))
    return bytes(result)


def reference(variant, module, offset, raw, source, locator, consumer, mode="HGR", **extra):
    return {"variant": variant, "file": module, "offset": offset, "length": len(raw),
            "original_hex": raw.hex(), "source": source, "locator": locator,
            "output_mode": mode, "consumer": consumer, **extra}


def generate():
    entries = {}
    identities = original_inputs()

    def add(identifier, original, ref, context, *, reason=None, codec="ascii-nul", **extra):
        key = identifier
        # A location may differ between editions; do not lose that English text.
        if key in entries and entries[key]["original"] != original:
            key += "." + ref["variant"]
        if key not in entries:
            protected = [{"token": match[0], "meaning": f"renderer byte ${match[1]}"}
                         for match in CONTROL_RE.finditer(original)]
            if extra.get("pronoun_substitution"):
                protected += [{"token": marker, "meaning": meaning} for marker, meaning in PRONOUNS.items()
                              if marker in original]
            entries[key] = {"id": key, "original": original, "context": context,
                            "codec": codec, "translatable": reason is None,
                            "status": "untranslated" if reason is None else "excluded",
                            "translation": None, "exclusion_reason": reason,
                            "protected_tokens": protected, "references": [], **extra}
        entries[key]["references"].append(ref)

    for variant in ("po", "disk1"):
        decoded = ROOT / "assets/decoded" / variant
        cdata = (ROOT / f"assets/{variant}/C.bin").read_bytes()
        dict_start, words = c_dictionary(cdata)
        offset = dict_start
        for index, word in enumerate(words):
            raw = word.encode("ascii") + b"\0"
            add(f"c.dictionary.{index:03d}", word,
                reference(variant, "C", offset, raw, "src/disk1/C.s", f"C_WORD_DICTIONARY[{index}]",
                          "N_EXPAND_TOKENIZED_TEXT", token=0x80 + index),
                "English S2 dictionary component; expanded sentences have separate translation entries",
                reason="Translate expanded S2 sentences. This English codec dictionary is not an independent sentence.")
            offset += len(raw)
        for group, records in read_json(decoded / "C-names.json").items():
            for index, record in enumerate(records):
                text = record.get("name", record.get("suffix"))
                offset = record["file_offset"]
                raw = cdata[offset:cdata.index(0, offset) + 1]
                reserved_name = group == "suspects" or (group == "detective_ranks" and index < 5)
                add(f"c.{group}.{index:02d}", text,
                    reference(variant, "C", offset, raw, "src/disk1/C.s", f"{group}[{index}]",
                              "N_DRAW_CURRENT_CITY_NAME / N_MEASURE_CENTERED_TEXT / N_APPEND_UI_TEXT",
                              runtime_address=0xD200 + offset,
                              usage_roles=["display", "input_comparison"] if reserved_name else ["display"]),
                    "weekday stem + weekday suffix + UI day fragment" if group.startswith("weekday") else group,
                    dynamic_group="weekday" if group.startswith("weekday") else group,
                    input_uses=[{"consumer": "N_CHECK_RESERVED_NAME -> N_COMPARE_INPUT_NAME",
                                 "original_english_must_be_preserved": True,
                                 "requirement": "Separate Korean display names from the original 15-entry English input blacklist"}]
                                if reserved_name else [])
        for group, records in read_json(decoded / "C-clues.json").items():
            for index, record in enumerate(records):
                offset = record["file_offset"]
                add(f"c.clue.{group}.{index:02d}", record["label"],
                    reference(variant, "C", offset, cdata[offset:cdata.index(0, offset) + 1],
                              "src/disk1/C.s", f"clues.{group}[{index}]", "N_CLUE_STRING_PTR_LO/HI"),
                    f"Interpol trait selector: {group}; value order is gameplay data")
        for record in read_json(decoded / "C-ui-text.json")["records"]:
            offset = record["load_address"] - 0xD200
            index = record["number"]
            add(f"c.ui.{index:03d}", visible_segments(record["segments"]),
                reference(variant, "C", offset, cdata[offset:cdata.index(0, offset) + 1],
                          f"assets/decoded/{variant}/C-ui-text.json", f"records[{index}].segments",
                          "N_SELECT_UI_TEXT -> N_DRAW_UI_TEXT / N_APPEND_UI_TEXT",
                          runtime_address=record["load_address"]),
                "HGR interface; fragments are combined by N; # Cases is a literal, not a pronoun",
                codec="controls-nul", dynamic_group="N UI assembly",
                input_tokens=([{"display": "Y/N", "accepted_bytes": [0x59, 0x4E],
                                "confirmation_byte": 0x0D}] if index in (21,26,94) else
                              [{"display": "Control-D", "accepted_bytes": [0x04]}] if index == 22 else []))
        # C's two resident service strings are not part of its UI dictionary.
        for name, text in (("she", "she"), ("he", "he")):
            raw = text.encode("ascii") + b"\0"
            offset = cdata.index(b"she\0he\0") + (0 if name == "she" else 4)
            add(f"c.service.{name}", text,
                reference(variant, "C", offset, raw, "src/disk1/C.s", f"C_PRONOUN_{name.upper()}",
                          "C_APPEND_5000_PRONOUN"), "Subject pronoun inserted into K clue text",
                dynamic_group="suspect sex")
        for module in ("I", "K"):
            data = (ROOT / f"assets/{variant}/{module}.bin").read_bytes()
            strings = read_json(ROOT / f"assets/text_source/{variant}/{module}.json")["strings"]
            offset = 0
            for index, text in enumerate(strings):
                raw = text.encode("ascii") + b"\0"
                add(f"{module.lower()}.{index:03d}", text,
                    reference(variant, module, offset, raw, f"assets/text_source/{variant}/{module}.json",
                              f"strings[{index}]", "C_APPEND_6000_STRING" if module == "I" else "C_APPEND_5000_TEXT"),
                    "Stolen treasure inserted into case briefing" if module == "I" else "Investigation response or suspect trait fragment",
                    pronoun_substitution=module == "K")
                offset += len(raw)
            if offset != len(data):
                raise ValueError(f"{variant}/{module}: incomplete string coverage")
        rdata = (ROOT / f"assets/{variant}/R.bin").read_bytes()
        offset = rdata.index(b"Carmen's gang has pulled another caper!\0")
        for index in range(4):
            raw = rdata[offset:rdata.index(0, offset) + 1]
            add(f"r.intro.{index:02d}", raw[:-1].decode("ascii"),
                reference(variant, "R", offset, raw, "src/disk1/R.s", f"R_SELECT_INTRO_STRING[{index}]",
                          "R_CENTER_INTRO_STRING -> R_DRAW_STRING_FROM_POINTER", runtime_address=0x6000 + offset),
                "Intro announcement, invitation or credit")
            offset += len(raw)
        ndata = (ROOT / f"assets/{variant}/N.bin").read_bytes()
        plural = bytes.fromhex("a9739900a0e6ac")  # LDA #'s'; STA $A000,Y; INC $AC
        offset = ndata.index(plural) + 1
        if ndata.find(plural, offset) >= 0:
            raise ValueError("Cannot identify the inline plural suffix uniquely")
        add("n.plural_suffix", "s",
            reference(variant, "N", offset, b"s", f"src/{variant}/N.s",
                      "N_REPORT_CASES_UNTIL_PROMOTION: LDA #$73", "inline append to $A000,Y",
                      runtime_address=0x6000 + offset),
            "English plural suffix after C UI MORE_CASES; Korean counters do not inflect. Empty translation requires removing the scalar append and cursor increment together.",
            codec="ascii-byte", dynamic_group="promotion case count")
        # Machine-readable references to explicitly excluded TEXT MODE messages.
        for module in ("WORLD.SYSTEM", "B"):
            data = (ROOT / f"assets/{variant}/{module}.bin").read_bytes()
            source = f"src/{variant}/{module}.s"
            lines = (ROOT / source).read_text().splitlines()
            for line_no, line in enumerate(lines, 1):
                match = re.search(r'(\w+):\s*\.asciiz\s+"([^"]*)"', line)
                if not match:
                    continue
                label, text = match.groups()
                if label.endswith(("PATH", "SIGNATURE")):
                    continue
                raw = text.encode("ascii") + b"\0"
                offset = data.index(raw)
                add(f"textmode.{module.lower()}.{label.lower()}", text,
                    reference(variant, module, offset, raw, source, f"line {line_no}: {label}",
                              "PRINT_MESSAGE -> ROM_COUT ($FDED)", mode="TEXT"),
                    "Boot error, RAM requirement, RAM disk warning or disk-insert prompt",
                    reason="User requirement: preserve every Apple II TEXT MODE message in English.")

    for variant, dictionary_variant, module in (("po", "po", "S2"), ("disk2", "disk1", "DATA.S2")):
        data = (ROOT / f"assets/{variant}/{module}.bin").read_bytes()
        _, words = c_dictionary((ROOT / f"assets/{dictionary_variant}/C.bin").read_bytes())
        for record in s2_index(data):
            start = record["start"]
            end = int.from_bytes(data[start:start + 2], "little")
            offset = start + 2
            parts = data[offset:start + end].split(b"\0")
            if parts[-2:] != [b"", b""]:
                raise ValueError("S2 record lacks final double NUL")
            # split's last element is after the final delimiter, not another field.
            for index, raw_text in enumerate(parts[:-1]):
                markup = markup_line(raw_text, words)
                raw = raw_text + b"\0"
                add(f"s2.city{record['number']:02d}.line{index:02d}", render_s2_line(raw_text, words),
                    reference(variant, module, offset, raw, f"assets/s2_source/{variant}/{record['number']:02d}.json",
                              f"lines[{index}]", "N_DRAW_CITY_DESCRIPTION" if index < 3 else "N_BUILD_PLACE_CLUE",
                              record=record["number"], string_index=index),
                    "City description (one of three)" if index < 3 else "Clue about the next route city, prefixed with suspect pronoun",
                    reason="Structural final empty S2 field; preserve record termination." if not raw_text else None,
                    codec="s2-markup-nul", original_markup=markup, pronoun_substitution=True,
                    dictionary_tokens=[{"token": "{" + words[b - 128] + "}", "byte": b}
                                       for b in raw_text if b >= 128])
                offset += len(raw)
            if offset != start + end:
                raise ValueError("S2 field coverage differs from header")

    dialog = read_json(ROOT / "assets/decoded/po/N-save-dialog.json")
    data = (ROOT / "assets/po/N.bin").read_bytes()
    offset = dialog["load_address"] - 0x6000
    add("n.save_dialog", visible_segments(dialog["segments"]),
        reference("po", "N", offset, data[offset:data.index(0, offset) + 1],
                  "assets/decoded/po/N-save-dialog.json", "segments", "N_DRAW_TEXT_POINTER_AT_X",
                  runtime_address=dialog["load_address"]), "800K HGR save confirmation; Return saves, Escape cancels",
        codec="controls-nul")
    for bitmap in read_json(ASSETS / "bitmap-text.json")["entries"]:
        for variant in ("po", "disk1"):
            module = bitmap["file"]
            folder = {"S": "s_source", "O": "o_source", "P": "p_source"}.get(module, "decoded")
            source = f"assets/{folder}/{variant}/{bitmap['source']}"
            ref = reference(variant, module, 0, b"", source, bitmap["context"],
                            "HGR image decompressor or direct D glyph selector",
                            source_sha256=sha256((ROOT / source).read_bytes()),
                            asset_sha256=sha256((ROOT / f"assets/{variant}/{module}.bin").read_bytes()))
            add(bitmap["id"], bitmap["original"], ref, bitmap["context"],
                reason=bitmap.get("reason"), codec="bitmap")
    return {"format": 1, "target": "128K Apple //e; 800K ProDOS edition", "original_inputs": identities,
            "approval": None, "entries": list(entries.values()),
            "format_rules": [{"source": "N_END_TEXT_SENTENCE", "bytes": [0x22,0x2E,0],
                              "role": "Quote-aware final ASCII period and NUL; a multibyte trail must not masquerade as the quote"},
                             {"source": "N_APPEND_ARREST_OBJECT", "bytes": [0x8D,0], "role": "Forced line break and NUL"},
                             {"source": "N_PRINT_DECIMAL_* / C_CLOCK_HOUR_*", "bytes": list(range(0x30,0x3A)),
                              "role": "Decimal game-state digits; preserve Arabic numerals"},
                             {"source": "N_DRAW_PLACE_EVENT_ZERO_FIRST_GLYPH", "bytes": [0x2D],
                              "role": "Dash used as an animation stroke, not narrative text"}],
            "scope_limits": ["Bitmap lettering survey and executable call-site coverage still require explicit inventory evidence",
                             "No approval is inferred from extraction or translation status"]}


def roundtrip(catalog):
    original_inputs()
    fresh = generate()
    for field in ("format", "target", "original_inputs", "format_rules"):
        if catalog.get(field) != fresh.get(field):
            raise ValueError(f"Original catalog header changed: {field}")
    expected = {e["id"]: e for e in fresh["entries"]}
    if len(catalog["entries"]) != len(expected):
        raise ValueError("Catalog entry count differs from current extraction")
    seen = set()
    rebuilt = {}
    ranges = {}
    for entry in catalog["entries"]:
        identifier = entry["id"]
        if identifier in seen or identifier not in expected:
            raise ValueError(f"Duplicate or unknown catalog ID: {identifier}")
        seen.add(identifier)
        truth = expected[identifier]
        for field in ("original", "original_markup", "codec", "references", "translatable", "protected_tokens",
                      "input_uses", "input_tokens", "pronoun_substitution", "dictionary_tokens", "dynamic_group"):
            if entry.get(field) != truth.get(field):
                raise ValueError(f"Original catalog field changed: {identifier}.{field}")
        for ref in entry["references"]:
            key = (ref["variant"], ref["file"])
            if entry["codec"] == "bitmap":
                # Text is drawn into a picture, so no ASCII inverse exists.
                # Check its native editable image/font representation instead.
                if key not in rebuilt:
                    from reconstruct import content_for, read_manifest
                    record = read_manifest()["images"][key[0]]["files"][key[1]]
                    rebuilt[key] = bytearray(content_for(*key, record))
                    ranges[key] = set()
                continue
            if entry["codec"] == "s2-markup-nul":
                v = "po" if ref["variant"] == "po" else "disk1"
                _, words = c_dictionary((ROOT / f"assets/{v}/C.bin").read_bytes())
                encoded = encode_line(entry["original_markup"], words) + b"\0"
            elif entry["codec"] == "controls-nul":
                encoded = encode_controls(entry["original"]) + b"\0"
            elif entry["codec"] == "ascii-byte":
                encoded = entry["original"].encode("ascii")
            else:
                encoded = entry["original"].encode("ascii") + b"\0"
            start, size = ref["offset"], ref["length"]
            if encoded.hex() != ref["original_hex"] or len(encoded) != size:
                raise ValueError(f"Catalog cannot reconstruct original bytes: {identifier}")
            if key not in rebuilt:
                rebuilt[key] = bytearray((ROOT / f"assets/{key[0]}/{key[1]}.bin").read_bytes())
                ranges[key] = set()
            if any(i in ranges[key] for i in range(start, start + size)):
                raise ValueError(f"Overlapping text references: {identifier}")
            ranges[key].update(range(start, start + size))
            rebuilt[key][start:start + size] = encoded
    results = []
    for (variant, module), data in sorted(rebuilt.items()):
        original = (ROOT / f"assets/{variant}/{module}.bin").read_bytes()
        if data != original:
            raise ValueError(f"Reconstructed text differs: {variant}/{module}")
        results.append({"variant": variant, "file": module, "sha256": sha256(data),
                        "reconstructed_text_bytes": len(ranges[variant, module]), "file_bytes": len(data)})
    return {"format": 1, "catalog_sha256": sha256(CATALOG.read_bytes()) if CATALOG.exists() else None,
            "entries": len(seen), "files": results,
            "counts": dict(Counter(e["id"].split(".")[0] for e in catalog["entries"])),
            "claim": "Every catalog text span re-encodes exactly; unclaimed code/graphics are preserved from immutable originals",
            "remaining": fresh["scope_limits"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("extract", "check"))
    args = parser.parse_args()
    if args.command == "extract":
        catalog = generate()
        if CATALOG.exists():
            previous = {entry["id"]: entry for entry in read_json(CATALOG)["entries"]}
            for entry in catalog["entries"]:
                prior = previous.get(entry["id"])
                if prior and entry["translatable"]:
                    entry["translation"] = prior["translation"]
                    # Extraction can preserve drafts, never approval.
                    entry["status"] = "draft" if prior["translation"] is not None else "untranslated"
                    if prior["original"] != entry["original"] or prior["references"] != entry["references"]:
                        entry["needs_review"] = "Original source changed since previous extraction"
        write_json(CATALOG, catalog)
    else:
        catalog = read_json(CATALOG)
    report = roundtrip(catalog)
    write_json(DOCS / "catalog-roundtrip.json", report)
    print(f"Verified {report['entries']} catalog entries across {len(report['files'])} original files")


if __name__ == "__main__":
    main()
