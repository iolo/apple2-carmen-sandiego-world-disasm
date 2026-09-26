"""Lossless editable views of C's interface text and packed bitmap tail."""

from sprite_assets import decode_sprites, encode_sprites


LOAD = 0xD200
UI_START = 0xE000
UI_END = 0xEC00
UI_TEXT_END = 0xEB3B
ICONS_END = 0xF979
ICON_COUNT = 30
ICON_LOW_TABLE = 0xDD00
ICON_HIGH_TABLE = 0xDD3E
ANIMATION_LOW_TABLE = 0xDD1E
ANIMATION_HIGH_TABLE = 0xDD5C
ANIMATION_BASE = 0x0E00
ANIMATION_GLYPH_BASE = 0x6B + ICON_COUNT


def decode_ui_text(data):
    block = data[UI_START - LOAD:UI_TEXT_END - LOAD]
    if not block.endswith(b"\0"):
        raise ValueError("C interface text lacks final NUL")
    records = []
    offset = 0
    for raw in block[:-1].split(b"\0"):
        if not raw:
            raise ValueError(f"Empty C interface text at {offset}")
        segments = []
        printable = bytearray()
        for byte in raw:
            if 32 <= byte <= 126:
                printable.append(byte)
            else:
                if printable:
                    segments.append({"text": printable.decode("ascii")})
                    printable.clear()
                if byte not in (0x80, 0x81, 0x82, 0x8D):
                    raise ValueError(f"Unknown C interface control ${byte:02X}")
                segments.append({"byte": byte})
        if printable:
            segments.append({"text": printable.decode("ascii")})
        records.append({"number": len(records), "file_offset": offset,
                        "load_address": UI_START + offset,
                        "segments": segments})
        offset += len(raw) + 1
    source = {"records": records, "padding_length": UI_END - UI_TEXT_END}
    if len(records) != 130 or encode_ui_text(source) != data[UI_START - LOAD:UI_END - LOAD]:
        raise ValueError("C interface text does not cover its exact source region")
    return source


def encode_ui_text(source):
    output = bytearray()
    for number, record in enumerate(source["records"]):
        if (record["number"] != number or record["file_offset"] != len(output)
                or record["load_address"] != UI_START + len(output)):
            raise ValueError(f"C interface text {number}: incorrect order or offset")
        for segment in record["segments"]:
            if set(segment) == {"text"}:
                encoded = segment["text"].encode("ascii")
                if any(byte < 32 or byte > 126 for byte in encoded):
                    raise ValueError(f"C interface text {number}: nonprintable text")
                output.extend(encoded)
            elif set(segment) == {"byte"} and segment["byte"] in (0x80, 0x81, 0x82, 0x8D):
                output.append(segment["byte"])
            else:
                raise ValueError(f"C interface text {number}: invalid segment")
        output.append(0)
    if len(output) != UI_TEXT_END - UI_START or source["padding_length"] != UI_END - UI_TEXT_END:
        raise ValueError("C interface text size or padding changed")
    output.extend(b"\0" * source["padding_length"])
    return bytes(output)


def decode_icons(data):
    lows = data[ICON_LOW_TABLE - LOAD:ICON_LOW_TABLE - LOAD + ICON_COUNT]
    highs = data[ICON_HIGH_TABLE - LOAD:ICON_HIGH_TABLE - LOAD + ICON_COUNT]
    addresses = [low | (high << 8) for low, high in zip(lows, highs)]
    if len(addresses) != ICON_COUNT or addresses[0] != UI_END or addresses[-1] != 0xF945:
        raise ValueError("Unexpected C icon pointer table")
    sprites = []
    for number, address in enumerate(addresses):
        end = addresses[number + 1] if number + 1 < ICON_COUNT else ICONS_END
        width, height = data[address - LOAD:address - LOAD + 2]
        body_end = address + 2 + height * ((width + 6) // 7)
        if not width or not height or body_end > end:
            raise ValueError(f"C icon {number}: invalid dimensions or pointer")
        raw = data[address - LOAD:body_end - LOAD]
        sprite = decode_sprites(raw)["sprites"][0]
        sprite.update({"number": number, "file_offset": address - UI_END,
                       "load_address": address,
                       "character_code": 0x8B + number,
                       "trailing_hex": data[body_end - LOAD:end - LOAD].hex()})
        sprites.append(sprite)
    source = {"sprites": sprites}
    if encode_icons(source) != data[UI_END - LOAD:ICONS_END - LOAD]:
        raise ValueError("C icons do not round trip exactly")
    return source


def encode_icons(source):
    sprites = source["sprites"]
    if len(sprites) != ICON_COUNT:
        raise ValueError("C needs 30 embedded icon records")
    output = bytearray()
    for number, sprite in enumerate(sprites):
        if (sprite["number"] != number or sprite["file_offset"] != len(output)
                or sprite["load_address"] != UI_END + len(output)
                or sprite["character_code"] != 0x8B + number):
            raise ValueError(f"C icon {number}: incorrect order or address")
        local = dict(sprite, number=0, file_offset=0)
        output.extend(encode_sprites({"sprites": [local]}))
        trailing = bytes.fromhex(sprite["trailing_hex"])
        if number == 27:
            if trailing != bytes.fromhex("787f7f0f"):
                raise ValueError("C icon 27 needs its four retained extra bytes")
        elif trailing:
            raise ValueError(f"C icon {number}: unexpected trailing bytes")
        output.extend(trailing)
    if len(output) != ICONS_END - UI_END:
        raise ValueError("C icon region changed size")
    return bytes(output)


def decode_animation_pointers(data, t_source, u_source):
    """Match C's split pointers to the T frames and reordered U sprites."""
    lows = data[ANIMATION_LOW_TABLE - LOAD:ANIMATION_LOW_TABLE - LOAD + 32]
    highs = data[ANIMATION_HIGH_TABLE - LOAD:ANIMATION_HIGH_TABLE - LOAD + 32]
    pointers = [low | (high << 8) for low, high in zip(lows, highs)]
    u_by_address = {ANIMATION_BASE + item["file_offset"]: item["number"]
                    for item in u_source["sprites"]}
    entries = []
    for index, pointer in enumerate(pointers):
        if index < 5:
            item = t_source["sprites"][index]
            if pointer != ANIMATION_BASE + item["file_offset"]:
                raise ValueError(f"C animation pointer {index} disagrees with T")
            entries.append({"index": index, "module": "T", "sprite_number": index,
                            "pointer_address": pointer})
        elif index < 31:
            if pointer not in u_by_address:
                raise ValueError(f"C animation pointer {index} does not address U")
            entries.append({"index": index, "module": "U",
                            "sprite_number": u_by_address[pointer],
                            "pointer_address": pointer})
        elif pointer != 0:
            raise ValueError("C animation pointer 31 must be zero")
        else:
            entries.append({"index": index, "module": None,
                            "sprite_number": None, "pointer_address": 0})
        # N reads these as continuations of the preceding 30 icon pointers.
        entries[-1]["glyph_index"] = ANIMATION_GLYPH_BASE + index
    if sorted(entry["sprite_number"] for entry in entries[5:31]) != list(range(26)):
        raise ValueError("C animation pointers do not cover all U sprites")
    source = {"base_address": ANIMATION_BASE, "entries": entries}
    if encode_animation_pointers(source, t_source, u_source) != (lows, highs):
        raise ValueError("C animation pointer table does not round trip")
    return source


def encode_animation_pointers(source, t_source, u_source):
    if source["base_address"] != ANIMATION_BASE or len(source["entries"]) != 32:
        raise ValueError("C animation pointer source has wrong base or count")
    pointers = []
    for index, entry in enumerate(source["entries"]):
        if entry["index"] != index:
            raise ValueError(f"C animation pointer {index}: wrong index")
        if entry["glyph_index"] != ANIMATION_GLYPH_BASE + index:
            raise ValueError(f"C animation pointer {index}: wrong glyph index")
        module = entry["module"]
        if index < 5 and (module != "T" or entry["sprite_number"] != index):
            raise ValueError(f"C animation pointer {index}: expected T frame {index}")
        if 5 <= index < 31 and module != "U":
            raise ValueError(f"C animation pointer {index}: expected U sprite")
        if index == 31:
            if module is not None or entry["sprite_number"] is not None:
                raise ValueError("C animation pointer 31: expected zero sentinel")
            pointer = 0
        else:
            sprites = t_source["sprites"] if module == "T" else u_source["sprites"]
            number = entry["sprite_number"]
            if not isinstance(number, int) or not 0 <= number < len(sprites):
                raise ValueError(f"C animation pointer {index}: invalid sprite number")
            pointer = ANIMATION_BASE + sprites[number]["file_offset"]
        if entry["pointer_address"] != pointer:
            raise ValueError(f"C animation pointer {index}: stale address")
        pointers.append(pointer)
    if sorted(entry["sprite_number"] for entry in source["entries"][5:31]) != list(range(26)):
        raise ValueError("C animation pointers must contain each U sprite once")
    return (bytes(pointer & 0xFF for pointer in pointers),
            bytes(pointer >> 8 for pointer in pointers))
