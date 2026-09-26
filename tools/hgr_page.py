"""Lossless editable view of the Apple II HGR splash page."""


PAGE_SIZE = 8192
FILE_SIZE = 8191
WIDTH = 280
HEIGHT = 192


def scanline_base(y):
    return ((y & 7) << 10) | (((y >> 3) & 7) << 7) | ((y >> 6) * 40)


VISIBLE_OFFSETS = tuple(scanline_base(y) + column
                        for y in range(HEIGHT) for column in range(40))
VISIBLE_OFFSET_SET = set(VISIBLE_OFFSETS)
HIDDEN_OFFSETS = tuple(offset for offset in range(FILE_SIZE)
                       if offset not in VISIBLE_OFFSET_SET)


def decode_hgr_page(data):
    if len(data) != FILE_SIZE:
        raise ValueError(f"A splash image must have {FILE_SIZE} bytes")
    rows = []
    for y in range(HEIGHT):
        values = data[scanline_base(y):scanline_base(y) + 40]
        pixels = "".join("#" if value & (1 << bit) else "."
                         for value in values for bit in range(7))
        phases = "".join("1" if value & 0x80 else "0" for value in values)
        rows.append({"pixels": pixels, "phase": phases})
    return {"format": "apple2-hgr-page", "width": WIDTH, "height": HEIGHT,
            "file_size": FILE_SIZE, "rows": rows,
            "hidden_hex": bytes(data[offset] for offset in HIDDEN_OFFSETS).hex()}


def encode_hgr_page(source):
    if (source.get("format") != "apple2-hgr-page" or source.get("width") != WIDTH
            or source.get("height") != HEIGHT or source.get("file_size") != FILE_SIZE
            or len(source.get("rows", [])) != HEIGHT):
        raise ValueError("Invalid A HGR page dimensions")
    hidden = bytes.fromhex(source["hidden_hex"])
    if len(hidden) != len(HIDDEN_OFFSETS):
        raise ValueError("Invalid A HGR hidden-byte count")
    page = bytearray(FILE_SIZE)
    for offset, value in zip(HIDDEN_OFFSETS, hidden):
        page[offset] = value
    for y, row in enumerate(source["rows"]):
        pixels, phases = row["pixels"], row["phase"]
        if (len(pixels) != WIDTH or set(pixels) - {"#", "."}
                or len(phases) != 40 or set(phases) - {"0", "1"}):
            raise ValueError(f"Invalid A HGR row {y}")
        for column in range(40):
            bits = pixels[column * 7:(column + 1) * 7]
            page[scanline_base(y) + column] = (
                sum(1 << bit for bit, pixel in enumerate(bits) if pixel == "#")
                | (0x80 if phases[column] == "1" else 0))
    return bytes(page)
