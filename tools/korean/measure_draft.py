"""Measure every complete draft against original buffers and native metrics.

This is a static preflight, not evidence of free RAM or a passing game image.
The layout model includes a required glyph-boundary fallback for overlong
words; original N backtracks indefinitely when such a word starts a line.
"""

import itertools
import sys

from .catalog import CATALOG, CONTROL_RE
from .common import DOCS, ROOT, read_json, write_json
from .encoding import GameEncoding, compile_fixtures

sys.path.insert(0, str(ROOT / "tools"))
from d_font import decode_d
from extract_assets import s2_index


def units(text):
    result, position = [], 0
    while position < len(text):
        control = CONTROL_RE.match(text, position)
        if control:
            result.append(control[0])
            position = control.end()
        else:
            result.append(text[position])
            position += 1
    return result


def wrap(text, widths, first_x, next_x, right_x, skip_line_marker_80=False):
    """Native strict right boundary and space wrapping, plus planned hard wrap."""
    tokens = units(text)
    lines, hard_breaks = [], []
    start, position, last_space, cursor = 0, 0, None, first_x
    while position < len(tokens):
        token = tokens[position]
        control = CONTROL_RE.fullmatch(token)
        if control and int(control[1], 16) >= 0x8D:
            lines.append("".join(tokens[start:position]))
            position += 1
        else:
            value = int(control[1], 16) if control else ord(token)
            width = widths[value] if value < 128 or control else 8
            if token == " ":
                last_space = position
            cursor += width
            if cursor < right_x:
                position += 1
                continue
            if last_space is not None:
                end = last_space
                position = last_space + 1
            else:
                if position == start:
                    raise ValueError("A single glyph is wider than its text window")
                end = position
                hard_breaks.append(position)
            lines.append("".join(tokens[start:end]))
        while position < len(tokens) and tokens[position] == " ":
            position += 1
        # Native typewriter formatting skips one $80 after a line separator
        # and its leading spaces. Spaces after the marker retain indentation.
        if skip_line_marker_80 and position < len(tokens) and tokens[position] == "<CTRL:80>":
            position += 1
        start, last_space, cursor = position, None, next_x
    if start < len(tokens):
        lines.append("".join(tokens[start:]))
    return {"lines": lines, "line_count": len(lines), "hard_breaks": hard_breaks,
            "final_empty_line": start == len(tokens)}


def measure():
    compiler = compile_fixtures()
    catalog = read_json(CATALOG)
    encoding = GameEncoding.from_catalog(catalog)
    entries = {e["id"]: e for e in catalog["entries"]}
    text = lambda identifier: entries[identifier]["translation"]
    glyphs = decode_d((ROOT / "assets/po/D.bin").read_bytes())["glyphs"]
    widths = {g["code"]: g["width_byte"] + 1 for g in glyphs}
    heights = {g["code"]: g["height"] for g in glyphs}

    def bottom(layout, top):
        def height(line):
            return max((heights[int(CONTROL_RE.fullmatch(token)[1], 16)] if CONTROL_RE.fullmatch(token)
                        else heights[ord(token)] if ord(token) < 128 else 8
                        for token in units(line)), default=0)
        return max((top + row * 10 + height(line) for row, line in enumerate(layout["lines"])), default=top)
    po = [e for e in entries.values() if any(r["variant"] == "po" for r in e["references"])]
    encoded = {e["id"]: encoding.entry(e) for e in po if e["translatable"] or not e["original"]}

    def size(value):
        return len(encoding.encode(value))

    def sentence(value):
        return value if value.endswith('"') else value + "."

    def expand(value, female, k_source=False):
        replacements = ({"#": text("c.service.she" if female else "c.service.he")} if k_source else
                        {"#": text(f"c.ui.{68 if female else 67:03}"),
                        "@": text(f"c.ui.{104 if female else 103:03}"),
                        "^": text("c.ui.105")})
        return "".join(replacements.get(c, c) for c in value)

    original = (ROOT / "assets/po/S2.bin").read_bytes()
    counts = (ROOT / "assets/po/N.bin").read_bytes()[0x8D78 - 0x6000:]
    if len(counts) != 360:
        raise ValueError("Original N category table extent changed")
    cities, descriptions, investigations = [], [], []
    covered={"c.ui.056", "c.ui.059", "c.ui.060", "c.ui.067", "c.ui.068", "c.ui.103", "c.ui.104", "c.ui.105",
             "c.service.he", "c.service.she"}
    investigation_combinations=0;retained_fields=[]
    trait_entries = [e for e in po if e["id"].startswith("k.") and int(e["id"][2:]) >= 8]
    for record in s2_index(original):
        number = record["number"]
        city_entries = {}
        for entry in po:
            for ref in entry["references"]:
                if ref["variant"] == "po" and ref["file"] == "S2" and ref.get("record") == number:
                    city_entries[ref["string_index"]] = entry
        raw = original[record["start"]:record["end"]]
        text_end = int.from_bytes(raw[:2], "little")
        original_lines = raw[2:text_end].split(b"\0")[:-1]
        if sorted(city_entries) != list(range(len(original_lines))):
            raise ValueError(f"City {number}: structural string order changed")
        lengths = [len(encoded[city_entries[i]["id"]]) for i in range(len(city_entries))]
        maxima, cursor = [], 3
        for count in counts[number * 12:(number + 1) * 12]:
            if count:
                maxima.append(max(lengths[cursor:cursor + count]))
            cursor += count
        if cursor > len(city_entries):
            raise ValueError(f"City {number}: category selection exceeds string count")
        cities.append({"city": number, "stored_text_bytes": sum(lengths),
                       "record_bytes": 2 + sum(lengths) + len(raw) - text_end,
                       "image_bytes_unchanged": len(raw) - text_end,
                       "description_with_nul": max(lengths[:3]),
                       "three_distinct_category_clues_with_nuls": sum(sorted(maxima, reverse=True)[:3])})
        for index in range(3):
            entry = city_entries[index]
            covered.add(entry["id"])
            value = sentence(entry["translation"])
            layout = wrap(value, widths, 156, 148, 273)
            descriptions.append({"id": entry["id"], "encoded_with_nul": size(value) + 1,
                                 "last_pixel_row_exclusive": bottom(layout, 6),
                                 **layout})
        worst = None
        maximum_bytes = 0
        for index in range(3, cursor):
            route = city_entries[index]
            covered.add(route["id"])
            for female, trait in itertools.product((False, True), trait_entries):
                covered.add(trait["id"])
                investigation_combinations+=1
                subject = text(f"c.ui.{60 if female else 59:03}")
                value = (sentence(subject + expand(route["translation"], female)) + text("c.ui.056")
                         + sentence(subject + expand(trait["translation"], female, k_source=True)))
                length = size(value) + 1
                maximum_bytes = max(maximum_bytes, length)
                layout = wrap(value, widths, 148, 148, 273)
                candidate = {"route_id": route["id"], "trait_id": trait["id"], "female": female,
                             "encoded_with_nul": length,
                             "text": value, "last_pixel_row_exclusive": bottom(layout, 26),
                             **layout}
                if worst is None or (candidate["last_pixel_row_exclusive"], length) > (worst["last_pixel_row_exclusive"], worst["encoded_with_nul"]):
                    worst = candidate
        investigations.append({"city": number, **worst, "maximum_encoded_with_nul": maximum_bytes})
        for index,entry in city_entries.items():
            if index<cursor or not entry["original"]:continue
            covered.add(entry["id"])
            for female in (False,True):
                value=sentence(text(f"c.ui.{60 if female else 59:03}")+expand(entry["translation"],female))
                layout=wrap(value,widths,148,148,273)
                last=bottom(layout,26)
                if last>136:raise ValueError('Retained clue preview exceeds panel: '+entry['id'])
                retained_fields.append({"id":entry["id"],"female":female,"text":value,"layout":layout,
                    "last_pixel_row_exclusive":last,"context":"Retained original nonempty tail outside this city row's native selector range; not a live-choice claim"})

    sizes = {"I": sum(len(encoded[e["id"]]) for e in po if e["id"].startswith("i.")),
             "K": sum(len(encoded[e["id"]]) for e in po if e["id"].startswith("k.")),
             "C_UI": sum(len(encoded[e["id"]]) for e in po if e["id"].startswith("c.ui.")),
             "C_names_before_DD00": sum(len(encoded[e["id"]]) for e in po
                 if e["id"].startswith(("c.cities.", "c.suspects.", "c.detective_ranks.", "c.weekdays.", "c.weekday_suffixes."))),
             "S2": 192 + sum(c["record_bytes"] for c in cities), "KF": compiler["font_bytes"]}
    maxima = {"stored_city_text": max(c["stored_text_bytes"] for c in cities),
              "selected_description_with_nul": max(c["description_with_nul"] for c in cities),
              "three_clues_with_nuls": max(c["three_distinct_category_clues_with_nuls"] for c in cities),
              "investigation_with_nul": max(c["maximum_encoded_with_nul"] for c in investigations),
              "description_rows": max(c["last_pixel_row_exclusive"] for c in descriptions),
              "investigation_rows": max(c["last_pixel_row_exclusive"] for c in investigations)}
    checks = {"I_boot_reservation": (sizes["I"], 4096), "K_boot_reservation": (sizes["K"], 4096),
              "C_UI_before_icons": (sizes["C_UI"], 3072), "C_names_before_DD00": (sizes["C_names_before_DD00"], 0xDD00 - 0xDB11),
              "stored_city_text_before_O": (maxima["stored_city_text"], 1792),
              "selected_description_page": (maxima["selected_description_with_nul"], 256),
              "selected_clues_before_image": (maxima["three_clues_with_nuls"], 512),
              "expanded_investigation_before_O": (maxima["investigation_with_nul"], 1792),
              "city_description_panel": (maxima["description_rows"], 136),
              "investigation_panel": (maxima["investigation_rows"], 136)}
    report = {"format": 1, "catalog_sha256": compiler["catalog_sha256"], "file_sizes": sizes,
              "maxima": maxima, "bounds": {key: {"required": used, "available": limit, "fits": used <= limit}
                                            for key, (used, limit) in checks.items()},
              "cities": cities, "descriptions": descriptions, "investigations": investigations,
              "covered_catalog_ids":sorted(covered),"investigation_combinations_measured":investigation_combinations,
              "retained_outside_selector_previews":retained_fields,
              "long_ascii_name": wrap("W" * 15, widths, 24, 24, 126),
              "required_runtime_changes": ["Decode glyphs before native control classification and glyph lookup",
                  "Disable English S2 dictionary expansion for Korean payloads",
                  "Use UI 105 for female object pronouns as well as male object pronouns",
                  "Synchronize C/N append-page cursors and remove the English plural instruction span",
                  "Bound glyph wrapping for oversized unspaced ASCII/Hangul fixtures; retain the original input pixel-width limit",
                  "Prove font/helper bank ownership and clock/bitmap lettering layouts in MAME"],
              "status": "pass; static city/trait bounds only; dynamic-message and native evidence are recorded separately"}
    write_json(DOCS / "draft-capacity.json", report)
    if any(not check["fits"] for check in report["bounds"].values()):
        raise ValueError("Draft exceeds a tested original bound; inspect draft-capacity.json before proceeding")
    return report


def main():
    report = measure()
    print(f"Static draft bounds pass; {report['file_sizes']['KF']} font bytes; native evidence is recorded separately")
    print(report["maxima"])


if __name__ == "__main__":
    main()
