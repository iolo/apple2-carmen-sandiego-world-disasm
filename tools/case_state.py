"""Lossless named representation of the game's 33-byte saved case state."""


FIELDS = (
    ("suspect", 0x00, 1),
    ("route_graph_index", 0x01, 1),
    ("route_index", 0x02, 1),
    ("route_slots", 0x03, 13),
    ("hideout_city", 0x10, 1),
    ("current_city", 0x11, 1),
    ("day", 0x12, 1),
    ("hour", 0x13, 1),
    ("deadline_day", 0x14, 1),
    ("deadline_hour", 0x15, 1),
    ("city_investigation_count", 0x16, 1),
    ("warrant_suspect", 0x17, 1),
    ("sound_enabled", 0x18, 1),
    ("treasure_text_index", 0x19, 1),
    ("city_menu_selection", 0x1A, 1),
    ("trait_filters", 0x1B, 6),
)
TRAIT_FILTER_ORDER = ("sex", "hobbies", "hair", "features", "vehicles", "food")


def decode_snapshot(data):
    if len(data) != 33:
        raise ValueError("Case snapshot must contain 33 bytes ($00-$20)")
    return {name: data[offset] if size == 1 else list(data[offset:offset + size])
            for name, offset, size in FIELDS}


def encode_snapshot(state):
    if not isinstance(state, dict) or set(state) != {name for name, _, _ in FIELDS}:
        raise ValueError("Case snapshot fields differ from the named $00-$20 layout")
    data = bytearray(33)
    for name, offset, size in FIELDS:
        values = [state[name]] if size == 1 else state[name]
        if not isinstance(values, list) or len(values) != size:
            raise ValueError(f"Case field {name} needs {size} byte values")
        if any(type(value) is not int or not 0 <= value <= 255 for value in values):
            raise ValueError(f"Case field {name} contains a value outside 0-255")
        data[offset:offset + size] = bytes(values)
    return bytes(data)
