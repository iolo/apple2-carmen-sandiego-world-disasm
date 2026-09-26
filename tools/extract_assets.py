#!/usr/bin/env python3
"""Readable views of confirmed text and indexed data, plus a HGR image preview."""

import json
from pathlib import Path
import re
import struct
import zlib

from reconstruct import ROOT, shift_tables_e
from d_font import decode_d, encode_d
from hgr_page import decode_hgr_page, encode_hgr_page, scanline_base
from c_embedded_assets import decode_ui_text, decode_icons, decode_animation_pointers
from j_routes import decode_j
from n_sounds import decode_n_sounds, decode_r_sounds
from speaker_audio import sound_previews
from case_state import decode_snapshot, encode_snapshot, TRAIT_FILTER_ORDER
from n_dialog import decode_dialog
from rle_image import (decode_image, decode_external_image, n_picture_records,
                       decode_s_source, encode_s_source,
                       decode_o_source, encode_o_source,
                       decode_p_source, encode_p_source)
from sprite_assets import decode_sprites, encode_sprites
from s2_image_codec import decode_stream, encode_stream
from s2_codec import c_dictionary, encode_line, markup_line


DEST = ROOT / "assets" / "decoded"


def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def null_strings(data):
    """Return every ASCII NUL-terminated string, including empty entries."""
    if not data.endswith(b"\0"):
        raise ValueError("Text file lacks a final NUL")
    result = []
    offset = 0
    for encoded in data[:-1].split(b"\0"):
        if any(byte < 32 or byte > 126 for byte in encoded):
            raise ValueError(f"Nonprintable text byte at offset {offset}")
        result.append({"offset": offset, "text": encoded.decode("ascii")})
        offset += len(encoded) + 1
    return result


def score_records(data):
    """F uses sixteen name bytes followed by three status bytes per record."""
    if len(data) != 256:
        raise ValueError("Unexpected F roster length")
    records = []
    for slot in range(13):
        offset = slot * 19
        record = data[offset:offset + 19]
        name = record[:16].rstrip(b"\xff").decode("ascii")
        empty = record == b"\xff" * 19
        records.append({"slot": slot, "offset": offset, "name": name,
                        "empty": empty,
                        "rank_index": None if empty else record[16],
                        "cases_solved": None if empty else record[17],
                        "saved_case": None if empty else record[18]})
    return {"record_size": 19, "slots": records,
            "tail_hex": data[13 * 19:].hex()}


def hall_of_fame_records(data):
    """G holds sixteen FF-padded, 16-byte former-detective names."""
    if len(data) != 256:
        raise ValueError("Unexpected G hall-of-fame length")
    slots = []
    for slot in range(16):
        record = data[slot * 16:(slot + 1) * 16]
        name = record.rstrip(b"\xff")
        if b"\xff" in name or any(byte < 32 or byte > 126 for byte in name):
            raise ValueError(f"Invalid G name in slot {slot}")
        slots.append({"slot": slot, "name": name.decode("ascii") if name else None})
    return {"record_size": 16, "slots": slots}


def e_shift_table_view(data):
    """Describe E's exact seven-page lookup formula."""
    if data != shift_tables_e():
        raise ValueError("E does not match the seven-page shift-table formula")
    return [
        {
            "page": shift,
            "offset": shift * 256,
            "first_half": "(input << shift) & 0x7f",
            "second_half": "input >> (7 - shift)",
            "input_range_per_half": "0x00-0x7f",
        }
        for shift in range(7)
    ]


def s2_index(data):
    # The first 192 bytes contain 64 little-endian 24-bit offsets. Only the
    # leading nonzero entries are used. The last nonzero entry is the EOF.
    offsets = [int.from_bytes(data[i:i + 3], "little") for i in range(0, 192, 3)]
    used = [offset for offset in offsets if offset]
    if not used or used[0] != 192 or used[-1] != len(data) or used != sorted(used):
        raise ValueError("Unexpected S2 offset table")
    result = []
    for number, (start, end) in enumerate(zip(used, used[1:])):
        region = data[start:end]
        runs = [{"offset": start + match.start(), "text": match.group().decode("ascii")}
                for match in re.finditer(rb"[\x20-\x7e]{5,}", region)]
        result.append({"number": number, "start": start, "end": end,
                       "length": end - start, "ascii_runs": runs})
    return result


def c_name_tables(data):
    start, words = c_dictionary(data)
    offset = start + sum(len(word) + 1 for word in words)
    groups = (("cities", 30), ("suspects", 10), ("detective_ranks", 6),
              ("weekdays", 7))
    result = {}
    for group, count in groups:
        entries = []
        for _ in range(count):
            end = data.index(0, offset)
            entries.append({"file_offset": offset,
                            "name": data[offset:end].decode("ascii")})
            offset = end + 1
        result[group] = entries
    if result["cities"][0]["name"] != "Athens" or result["weekdays"][-1]["name"] != "Sun":
        raise ValueError("Unexpected C name tables")
    suffixes = []
    for day in result["weekdays"]:
        end = data.index(0, offset)
        suffix = data[offset:end].decode("ascii")
        suffixes.append({"file_offset": offset, "suffix": suffix,
                         "full_name": day["name"] + suffix + "day"})
        offset = end + 1
    if offset != 0xDD00 - 0xD200 or [item["full_name"] for item in suffixes] != [
            "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]:
        raise ValueError("Unexpected C weekday suffixes")
    result["weekday_suffixes"] = suffixes
    return result


def c_clue_labels(data):
    marker = b"Male\0Female\0Tennis\0"
    offset = data.find(marker)
    if offset < 0 or data.find(marker, offset + 1) >= 0:
        raise ValueError("Cannot locate C clue labels uniquely")
    groups = (("sex", 2), ("hobbies", 6), ("hair", 4),
              ("features", 5), ("vehicles", 4), ("food", 2))
    result = {}
    for group, count in groups:
        entries = []
        for _ in range(count):
            end = data.index(0, offset)
            entries.append({"file_offset": offset,
                            "label": data[offset:end].decode("ascii")})
            offset = end + 1
        result[group] = entries
    if result["food"][-1]["label"] != "Seafood":
        raise ValueError("Unexpected C clue labels")
    return result


def r_custom_glyphs(data):
    """Decode R's eight extra bitmap glyphs after its text and tables."""
    base_address = 0x6CDE
    base_offset = base_address - 0x6000
    decoded = decode_sprites(data[base_offset:])
    if len(decoded["sprites"]) != 8 or encode_sprites(decoded) != data[base_offset:]:
        raise ValueError("R custom glyphs do not cover the exact file tail")
    pointer_offset = 0x6C35 - 0x6000
    lows = data[pointer_offset:pointer_offset + 8]
    highs = data[pointer_offset + 8:pointer_offset + 16]
    pointers = [low | (high << 8) for low, high in zip(lows, highs)]
    addresses = [base_address + sprite["file_offset"]
                 for sprite in decoded["sprites"]]
    if pointers != addresses:
        raise ValueError("R glyph pointer table disagrees with record boundaries")
    for sprite, address in zip(decoded["sprites"], addresses):
        sprite["load_address"] = address
        sprite["character_code"] = 0x8B + sprite["number"]
    return decoded


def n_suspect_traits(data, variant, names, clues):
    """Join N's ten-by-six trait matrix to the suspect and clue names in C."""
    matrix_address = {"disk1": 0x8CDB, "po": 0x8CDF}[variant]
    limits_address = {"disk1": 0x8CB0, "po": 0x8CB4}[variant]
    categories = ("sex", "hobbies", "hair", "features", "vehicles", "food")
    expected_limits = bytes(len(clues[name]) - 1 for name in categories)
    if data[limits_address - 0x6000:limits_address - 0x6000 + 6] != expected_limits:
        raise ValueError(f"{variant}/N clue limits disagree with C labels")
    if len(names["suspects"]) != 10:
        raise ValueError(f"{variant}/C needs ten suspect names")
    matrix = data[matrix_address - 0x6000:matrix_address - 0x6000 + 60]
    if len(matrix) != 60:
        raise ValueError(f"{variant}/N suspect matrix is truncated")
    suspects = []
    for number, suspect in enumerate(names["suspects"]):
        values = matrix[number * 6:(number + 1) * 6]
        traits = {}
        for category, value in zip(categories, values):
            labels = clues[category]
            if value >= len(labels):
                raise ValueError(f"{variant}/N suspect {number}: invalid {category} value")
            traits[category] = {"value": value, "label": labels[value]["label"]}
        suspects.append({"number": number, "name": suspect["name"], "traits": traits})
    return {"file_offset": matrix_address - 0x6000,
            "category_order": list(categories), "suspects": suspects}


def n_city_map(data, variant, cities):
    """Join city marker positions and the route line's two-pixel X units."""
    address = {"disk1": 0x8C0A, "po": 0x8C0E}[variant]
    offset = address - 0x6000
    triples = data[offset:offset + 90]
    route_x = data[offset + 90:offset + 120]
    if len(cities) != 30 or len(triples) != 90 or len(route_x) != 30:
        raise ValueError(f"{variant}/N: unexpected city-map table extent")
    rows = []
    for number, city in enumerate(cities):
        column, bit, y = triples[number * 3:(number + 1) * 3]
        x = column * 7 + bit
        logical_x = route_x[number]
        if column >= 40 or bit >= 7 or y >= 192 or logical_x != x // 2:
            raise ValueError(f"{variant}/N: invalid city-map position {number}")
        rows.append({"number": number, "city": city,
                     "hgr_byte_column": column, "hgr_bit_offset": bit,
                     "map_anchor_pixel_x": x, "map_anchor_pixel_y": y,
                     "route_x": logical_x, "route_pixel_x": logical_x * 2})
    return {"position_table_address": address,
            "route_x_table_address": address + 90,
            "route_x_unit_pixels": 2, "cities": rows}


def n_city_clue_counts(data, variant, cities, s2_records):
    """Relate N's twelve clue counts per route city to its S2 text groups."""
    address = {"disk1": 0x8D74, "po": 0x8D78}[variant]
    offset = address - 0x6000
    raw = data[offset:]
    if len(raw) != 30 * 12 or len(cities) != 30 or len(s2_records) != 30:
        raise ValueError(f"{variant}: unexpected city clue-count extent")
    rows = []
    for number, city in enumerate(cities):
        record = s2_records[number]
        if record["number"] != number:
            raise ValueError(f"{variant}: S2 city order disagrees with C")
        counts = raw[number * 12:(number + 1) * 12]
        total = sum(counts)
        lines = record["lines"]
        if sum(count > 0 for count in counts) < 3 or 3 + total > len(lines):
            raise ValueError(f"{variant}: city {number} has invalid clue counts")
        cursor = 3
        groups = []
        for category, count in enumerate(counts):
            groups.append({"category": category, "count": count,
                           "lines": [{"number": index, "text": lines[index]["text"]}
                                     for index in range(cursor, cursor + count)]})
            cursor += count
        rows.append({"number": number, "city": city,
                     "table_address": address + number * 12,
                     "total_selectable_lines": total, "groups": groups,
                     "lines_outside_selector": [
                         {"number": index, "text": lines[index]["text"]}
                         for index in range(cursor, len(lines))]})
    return {"first_table_address": address, "row_size": 12, "cities": rows}


def render_s2_line(data, words, pronouns=None):
    """Expand dictionary bytes and, optionally, the game's pronoun markers."""
    result = []
    for index, byte in enumerate(data):
        if byte >= 128:
            result.append(words[byte - 128])
            if index + 1 < len(data) and data[index + 1] not in b"!,.:":
                result.append(" ")
        elif 32 <= byte <= 126:
            marker = chr(byte)
            result.append(pronouns.get(marker, marker) if pronouns else marker)
        else:
            raise ValueError(f"Unexpected S2 text byte ${byte:02X}")
    return "".join(result).rstrip()


def s2_text(data, index, words):
    female = {"#": "she", "@": "her", "^": "her"}
    male = {"#": "he", "@": "his", "^": "him"}
    result = []
    for item in index:
        record = data[item["start"]:item["end"]]
        text_end = int.from_bytes(record[:2], "little")
        if not 2 < text_end < len(record) or not record[2:text_end].endswith(b"\0\0"):
            raise ValueError(f"Unexpected S2 text boundary in record {item['number']}")
        lines = []
        offset = 2
        for encoded in record[2:text_end].split(b"\0"):
            if encoded:
                lines.append({"file_offset": item["start"] + offset,
                              "text": render_s2_line(encoded, words),
                              "female_preview": render_s2_line(encoded, words, female),
                              "male_preview": render_s2_line(encoded, words, male)})
            offset += len(encoded) + 1
        result.append({"number": item["number"], "text_end_in_record": text_end,
                       "binary_start_in_file": item["start"] + text_end,
                       "lines": lines})
    return result


def split_s2(data, variant):
    index = s2_index(data)
    directory = ROOT / "assets" / "s2" / variant
    directory.mkdir(parents=True, exist_ok=True)
    for item in index:
        (directory / f"{item['number']:02d}.bin").write_bytes(data[item["start"]:item["end"]])
    return index


def split_s2_source(data, index, variant, words):
    directory = ROOT / "assets" / "s2_source" / variant
    directory.mkdir(parents=True, exist_ok=True)
    for item in index:
        record = data[item["start"]:item["end"]]
        text_end = int.from_bytes(record[:2], "little")
        if not 2 < text_end < len(record):
            raise ValueError(f"Unexpected S2 text pointer in record {item['number']}")
        encoded = record[2:text_end]
        lines = [markup_line(line, words) for line in encoded.split(b"\0")]
        if b"\0".join(encode_line(line, words) for line in lines) != encoded:
            raise ValueError(f"S2 markup round trip failed for record {item['number']}")
        stem = f"{item['number']:02d}"
        save_json(directory / (stem + ".json"), {"lines": lines})
        (directory / (stem + "-binary.bin")).write_bytes(record[text_end:])


def s2_image_views(variant, cities):
    directory = ROOT / "assets" / "s2_source" / variant
    result = []
    for number, city in enumerate(cities):
        binary = (directory / f"{number:02d}-binary.bin").read_bytes()
        stream = decode_stream(binary)
        if encode_stream(stream) != binary:
            raise ValueError(f"{variant}/S2 image {number}: stream does not round trip")
        save_json(directory / f"{number:02d}-image.json", stream)
        header, page, consumed = decode_external_image(
            binary, 1, 1, 19, 38, 187, binary[0], allow_short_tail=True)
        missing = header["missing_pixels_at_eof"]
        if consumed != len(binary) or missing != (3 if number == 8 else 0):
            raise ValueError(f"{variant}/S2 image {number}: unexpected extent or tail")
        (DEST / variant / f"S2-{number:02d}.png").write_bytes(hgr_png(page))
        result.append({"number": number, "city": city, "binary_length": len(binary),
                       **header})
    return result


def case_snapshot_view(snapshot, names, clues, treasures):
    """Name confirmed fields without inferring the extent of a stale route."""
    if len(snapshot) != 33:
        raise ValueError("Case snapshot must contain zero-page $00-$20")

    def named(value, group):
        entries = names[group]
        return {"value": value,
                "name": entries[value]["name"] if value < len(entries) else None}

    route = [named(value, "cities") for value in snapshot[3:16]]
    categories = ("sex", "hobbies", "hair", "features", "vehicles", "food")
    filters = {}
    for category, value in zip(categories, snapshot[0x1B:0x21]):
        labels = clues[category]
        filters[category] = {
            "value": value, "unset": value == 0xFF,
            "label": labels[value]["label"] if value < len(labels) else None}
    return {
        "suspect": named(snapshot[0], "suspects"),
        "route_graph_index": snapshot[1],
        "route_index": snapshot[2],
        "route_slots": route,
        "starting_city": route[0],
        "hideout_city": named(snapshot[0x10], "cities"),
        "current_city": named(snapshot[0x11], "cities"),
        "clock": {"day": named(snapshot[0x12], "weekdays"), "hour": snapshot[0x13]},
        "deadline": {"day": named(snapshot[0x14], "weekdays"), "hour": snapshot[0x15]},
        "city_investigation_count": snapshot[0x16],
        "warrant_suspect": named(snapshot[0x17], "suspects"),
        "sound_enabled_value": snapshot[0x18],
        "treasure": {"value": snapshot[0x19], "text":
                     treasures[snapshot[0x19]] if snapshot[0x19] < len(treasures) else None},
        "city_menu_selection": {"value": snapshot[0x1A], "label":
                                ("See Connections", "Depart by Plane", "Investigate",
                                 "Visit Interpol")[snapshot[0x1A]]
                                if snapshot[0x1A] < 4 else None},
        "trait_filters": filters,
    }


def h_case_views(data, roster, names, clues, treasures):
    """Describe H snapshots and F's separate saved-case flags."""
    if len(data) != 13 * 256 or len(roster["slots"]) != 13:
        raise ValueError("Unexpected H/F saved-case slot count")
    slots = []
    for number, detective in enumerate(roster["slots"]):
        page = data[number * 256:(number + 1) * 256]
        unused = page == b"\xff" * 256
        slots.append({"slot": number, "detective": detective["name"],
                      "unused_page": unused,
                      "roster_saved_case_flag": detective["saved_case"],
                      "resume_flag_set": detective["saved_case"] not in (None, 0),
                      "snapshot": None if unused else
                      case_snapshot_view(page[:33], names, clues, treasures)})
    return {"snapshot_range": "$00-$20", "route_slots_note":
            "All thirteen stored slots are shown; values after the final hideout may be stale.",
            "slots": slots}


def split_h(data, variant, roster):
    if len(data) != 13 * 256:
        raise ValueError("Unexpected H case-state length")
    directory = ROOT / "assets" / "h" / variant
    directory.mkdir(parents=True, exist_ok=True)
    index = []
    source_slots = []
    for slot in range(13):
        page = data[slot * 256:(slot + 1) * 256]
        (directory / f"{slot:02d}.bin").write_bytes(page)
        all_ff = page == b"\xff" * 256
        if not all_ff and page[33:] != b"\0" * 223:
            raise ValueError(f"H slot {slot} has data beyond its zero-page snapshot")
        detective = roster["slots"][slot]["name"]
        index.append({"slot": slot, "detective": roster["slots"][slot]["name"],
                      "all_ff": all_ff,
                      "non_ff_bytes": sum(byte != 255 for byte in page),
                      "first_33_hex": page[:33].hex()})
        state = None if all_ff else decode_snapshot(page[:33])
        if state is not None and encode_snapshot(state) != page[:33]:
            raise ValueError(f"H slot {slot}: named state does not round trip")
        source_slots.append({"slot": slot, "detective": detective, "unused": all_ff,
                             "case_state": state})
    save_json(DEST / variant / "H.json", {
        "snapshot_range": "$00-$20", "trait_filter_order": list(TRAIT_FILTER_ORDER),
        "slots": source_slots})
    return index


def png_chunk(kind, data):
    payload = kind + data
    return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload))


def hgr_png(data):
    """Render an 8 KiB Apple II HGR page in monochrome, preserving all pixels."""
    page = data.ljust(8192, b"\x00")
    if len(page) != 8192:
        raise ValueError("HGR page is larger than 8192 bytes")
    scanlines = []
    for y in range(192):
        base = scanline_base(y)
        line = bytearray(b"\x00")
        for column in range(40):
            value = page[base + column]
            line.extend(255 if value & (1 << bit) else 0 for bit in range(7))
        scanlines.append(bytes(line))
    header = struct.pack(">2I5B", 280, 192, 8, 0, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header)
            + png_chunk(b"IDAT", zlib.compress(b"".join(scanlines), 9))
            + png_chunk(b"IEND", b""))


def font_png(source):
    """Render printable D glyphs as a 16-column monochrome contact sheet."""
    cell_width, cell_height, scale = 12, 12, 3
    width, height = 16 * cell_width * scale, 6 * cell_height * scale
    scanlines = []
    glyphs = source["glyphs"]
    for y in range(height):
        logical_y = y // scale
        glyph_row, pixel_y = divmod(logical_y, cell_height)
        line = bytearray(b"\x00")
        for x in range(width):
            logical_x = x // scale
            glyph_col, pixel_x = divmod(logical_x, cell_width)
            glyph_index = glyph_row * 16 + glyph_col
            pixel = False
            if glyph_index < 95 and 0 < pixel_y <= glyphs[glyph_index]["height"]:
                glyph = glyphs[glyph_index]
                if 0 < pixel_x <= glyph["width_byte"]:
                    byte_index, bit = divmod(pixel_x - 1, 7)
                    pixel = glyph["rows"][pixel_y - 1][byte_index * 8 + bit] == "#"
            line.append(255 if pixel else 0)
        scanlines.append(bytes(line))
    header = struct.pack(">2I5B", width, height, 8, 0, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header)
            + png_chunk(b"IDAT", zlib.compress(b"".join(scanlines), 9))
            + png_chunk(b"IEND", b""))


def sprite_png(sprite, scale=3):
    width, height = sprite["width"] * scale, sprite["height"] * scale
    scanlines = []
    for y in range(height):
        row = sprite["rows"][y // scale]
        line = bytearray(b"\x00")
        for x in range(width):
            pixel_x = x // scale
            pixel = row[(pixel_x // 7) * 8 + pixel_x % 7] == "#"
            line.append(255 if pixel else 0)
        scanlines.append(bytes(line))
    header = struct.pack(">2I5B", width, height, 8, 0, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header)
            + png_chunk(b"IDAT", zlib.compress(b"".join(scanlines), 9))
            + png_chunk(b"IEND", b""))


def split_s_images(data, variant):
    # These four addresses are the literal $69BE decoder arguments in R.
    starts = (0x0000, 0x03E0, 0x07A0, 0x0F60)
    ends = starts[1:] + (len(data),)
    directory = ROOT / "assets" / "s" / variant
    directory.mkdir(parents=True, exist_ok=True)
    source_directory = ROOT / "assets" / "s_source" / variant
    index = []
    for number, (start, next_start) in enumerate(zip(starts, ends)):
        header, page, consumed = decode_image(data, start)
        if consumed > next_start or any(data[consumed:next_start]):
            raise ValueError(f"{variant}/S image {number}: unexpected padding")
        chunk = data[start:next_start]
        (directory / f"{number:02d}.bin").write_bytes(chunk)
        source = decode_s_source(chunk, number, 0x7800 + start)
        if encode_s_source(source, number, 0x7800 + start, len(chunk)) != chunk:
            raise ValueError(f"{variant}/S image {number}: source does not round trip")
        save_json(source_directory / f"{number:02d}.json", source)
        (DEST / variant / f"S-{number:02d}.png").write_bytes(hgr_png(page))
        index.append({"number": number, "file_offset": start,
                      "loaded_address": 0x7800 + start,
                      "compressed_length": consumed - start,
                      "padding_length": next_start - consumed,
                      **header})
    return index


def split_n_images(base, variant):
    records = n_picture_records((base / "N.bin").read_bytes(), variant)
    o_data = (base / "O.bin").read_bytes()
    o_directory = ROOT / "assets" / "o" / variant
    o_directory.mkdir(parents=True, exist_ok=True)
    o_source_directory = ROOT / "assets" / "o_source" / variant
    o_records = []
    ordered = sorted(records[1:5], key=lambda item: item["loaded_address"])
    for item, next_item in zip(ordered, ordered[1:] + [None]):
        start = item["loaded_address"] - 0xA700
        next_start = (next_item["loaded_address"] - 0xA700
                      if next_item else len(o_data))
        header, page, consumed = decode_external_image(
            o_data, start, item["x_start"], item["x_end"],
            item["y_start"], item["y_end"], item["scanline_stride"])
        if consumed > next_start or any(o_data[consumed:next_start]):
            raise ValueError(f"{variant}/O picture {item['number']}: unexpected padding")
        chunk = o_data[start:next_start]
        (o_directory / f"{item['number']:02d}.bin").write_bytes(chunk)
        source = decode_o_source(chunk, item)
        if encode_o_source(source, item, len(chunk)) != chunk:
            raise ValueError(f"{variant}/O image {item['number']}: source does not round trip")
        save_json(o_source_directory / f"{item['number']:02d}.json", source)
        (DEST / variant / f"O-{item['number']:02d}.png").write_bytes(hgr_png(page))
        o_records.append({**item, "file_offset": start,
                          "compressed_length": consumed - start,
                          "padding_length": next_start - consumed,
                          "marker": header["marker"]})
    p_data = (base / "P.bin").read_bytes()
    p_source = decode_p_source(p_data, records)
    if encode_p_source(p_source, records) != p_data:
        raise ValueError(f"{variant}/P source does not round trip")
    save_json(ROOT / "assets" / "p_source" / variant / "P.json", p_source)
    p_records = []
    for number in (0, 5):
        item = records[number]
        start = item["loaded_address"] - 0x1100
        stride = p_data[0] if number == 0 else item["scanline_stride"]
        header, page, consumed = decode_external_image(
            p_data, start, item["x_start"], item["x_end"],
            item["y_start"], item["y_end"], stride)
        if consumed > len(p_data) or (number == 5 and consumed != len(p_data)):
            raise ValueError(f"{variant}/P picture {number}: unexpected extent")
        (DEST / variant / f"P-{number:02d}.png").write_bytes(hgr_png(page))
        p_records.append({**item, "file_offset": start,
                          "compressed_length_to_end": consumed - start,
                          "effective_scanline_stride": stride,
                          "marker": header["marker"],
                          "unused_copies_in_final_run":
                              header["unused_copies_in_final_run"]})
    return o_records, p_records


def main():
    for variant in ("disk1", "po"):
        base = ROOT / "assets" / variant
        for name in ("I", "K"):
            strings = null_strings((base / (name + ".bin")).read_bytes())
            save_json(DEST / variant / (name + ".json"), strings)
            save_json(ROOT / "assets" / "text_source" / variant / (name + ".json"),
                      {"strings": [item["text"] for item in strings]})
        roster = score_records((base / "F.bin").read_bytes())
        save_json(DEST / variant / "F.json", roster)
        save_json(DEST / variant / "G.json",
                  hall_of_fame_records((base / "G.bin").read_bytes()))
        save_json(DEST / variant / "H-index.json",
                  split_h((base / "H.bin").read_bytes(), variant, roster))
        save_json(DEST / variant / "E-shifts.json",
                  e_shift_table_view((base / "E.bin").read_bytes()))
        c_data = (base / "C.bin").read_bytes()
        dictionary_offset, words = c_dictionary(c_data)
        save_json(DEST / variant / "C-dictionary.json",
                  {"file_offset": dictionary_offset,
                   "entries": [{"byte": 128 + index, "word": word}
                               for index, word in enumerate(words)]})
        name_tables = c_name_tables((base / "C.bin").read_bytes())
        save_json(DEST / variant / "C-names.json", name_tables)
        clue_labels = c_clue_labels((base / "C.bin").read_bytes())
        save_json(DEST / variant / "C-clues.json", clue_labels)
        save_json(DEST / variant / "H-cases.json",
                  h_case_views((base / "H.bin").read_bytes(), roster,
                               name_tables, clue_labels,
                               [row["text"] for row in null_strings((base / "I.bin").read_bytes())]))
        save_json(DEST / variant / "C-ui-text.json", decode_ui_text(c_data))
        c_icons = decode_icons(c_data)
        save_json(DEST / variant / "C-icons.json", c_icons)
        for icon in c_icons["sprites"]:
            (DEST / variant / f"C-icon-{icon['number']:02d}.png").write_bytes(
                sprite_png(icon))
        save_json(DEST / variant / "N-suspect-traits.json",
                  n_suspect_traits((base / "N.bin").read_bytes(), variant,
                                   name_tables, clue_labels))
        cities = [entry["name"] for entry in name_tables["cities"]]
        save_json(DEST / variant / "N-city-map.json",
                  n_city_map((base / "N.bin").read_bytes(), variant, cities))
        save_json(DEST / variant / "J-routes.json",
                  decode_j((base / "J.bin").read_bytes(), cities))
        n_data = (base / "N.bin").read_bytes()
        n_sounds = decode_n_sounds(n_data, variant)
        save_json(DEST / variant / "N-sounds.json", n_sounds)
        save_json(DEST / variant / "N-audio.json",
                  sound_previews(n_data, "N", variant, n_sounds, DEST / variant))
        if variant == "po":
            save_json(DEST / variant / "N-save-dialog.json",
                      decode_dialog((base / "N.bin").read_bytes()))
        r_data = (base / "R.bin").read_bytes()
        r_sounds = decode_r_sounds(r_data, variant)
        save_json(DEST / variant / "R-sounds.json", r_sounds)
        save_json(DEST / variant / "R-audio.json",
                  sound_previews(r_data, "R", variant, r_sounds, DEST / variant))
        r_glyphs = r_custom_glyphs((base / "R.bin").read_bytes())
        save_json(DEST / variant / "R-glyphs.json", r_glyphs)
        for glyph in r_glyphs["sprites"]:
            (DEST / variant / f"R-glyph-{glyph['number']:02d}.png").write_bytes(
                sprite_png(glyph))
        font_data = (base / "D.bin").read_bytes()
        font = decode_d(font_data)
        if encode_d(font) != font_data:
            raise ValueError(f"{variant}/D font does not round trip")
        save_json(DEST / variant / "D-font.json", font)
        (DEST / variant).mkdir(parents=True, exist_ok=True)
        splash = (base / "A.bin").read_bytes()
        splash_source = decode_hgr_page(splash)
        if encode_hgr_page(splash_source) != splash:
            raise ValueError(f"{variant}/A HGR page does not round trip")
        save_json(DEST / variant / "A-hgr.json", splash_source)
        (DEST / variant / "A.png").write_bytes(hgr_png(splash))
        (DEST / variant / "D-ascii.png").write_bytes(font_png(font))
        save_json(DEST / variant / "S-images.json",
                  split_s_images((base / "S.bin").read_bytes(), variant))
        sprite_sources = {}
        for name in ("T", "U"):
            bitmap_data = (base / (name + ".bin")).read_bytes()
            sprite_source = decode_sprites(bitmap_data)
            sprite_sources[name] = sprite_source
            if encode_sprites(sprite_source) != bitmap_data:
                raise ValueError(f"{variant}/{name}: sprites do not round trip")
            save_json(DEST / variant / f"{name}-sprites.json", sprite_source)
            for sprite in sprite_source["sprites"]:
                number = sprite["number"]
                (DEST / variant / f"{name}-{number:02d}.png").write_bytes(
                    sprite_png(sprite))
        save_json(DEST / variant / "C-animation-pointers.json",
                  decode_animation_pointers(c_data, sprite_sources["T"], sprite_sources["U"]))
        o_records, p_records = split_n_images(base, variant)
        save_json(DEST / variant / "O-images.json", o_records)
        save_json(DEST / variant / "P-images.json", p_records)
    for variant, name in (("disk2", "DATA.S2"), ("po", "S2")):
        data = (ROOT / "assets" / variant / (name + ".bin")).read_bytes()
        index = split_s2(data, variant)
        save_json(DEST / variant / "S2-index.json", index)
        dictionary_variant = "disk1" if variant == "disk2" else "po"
        _, words = c_dictionary((ROOT / "assets" / dictionary_variant / "C.bin").read_bytes())
        text_records = s2_text(data, index, words)
        save_json(DEST / variant / "S2-text.json", text_records)
        split_s2_source(data, index, variant, words)
        cities = [entry["name"] for entry in c_name_tables(
            (ROOT / "assets" / dictionary_variant / "C.bin").read_bytes())["cities"]]
        save_json(DEST / dictionary_variant / "N-city-clue-counts.json",
                  n_city_clue_counts(
                      (ROOT / "assets" / dictionary_variant / "N.bin").read_bytes(),
                      dictionary_variant, cities, text_records))
        save_json(DEST / variant / "S2-images.json", s2_image_views(variant, cities))
    print("wrote decoded text, font, sound, bitmap, HGR, and S2 views under assets/")


if __name__ == "__main__":
    main()
