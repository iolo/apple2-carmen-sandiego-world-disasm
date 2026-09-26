"""Lossless decoder for the variable-size bitmap glyphs in file D."""


BASE = 0xB900
POINTER_COUNT = 112
GLYPH_COUNT = 107
DATA_START = POINTER_COUNT * 2


def decode_d(data):
    pointers = [data[index] | (data[POINTER_COUNT + index] << 8)
                for index in range(POINTER_COUNT)]
    if pointers[0] != BASE + DATA_START or pointers[GLYPH_COUNT:] != [0] * 5:
        raise ValueError("Unexpected D glyph pointer table")
    if pointers[:GLYPH_COUNT] != sorted(pointers[:GLYPH_COUNT]):
        raise ValueError("D glyph pointers are not ordered")
    glyphs = []
    for index in range(GLYPH_COUNT):
        start = pointers[index] - BASE
        end = pointers[index + 1] - BASE if index + 1 < GLYPH_COUNT else len(data)
        record = data[start:end]
        if len(record) < 2:
            raise ValueError(f"D glyph {index}: truncated header")
        width_byte, height = record[:2]
        stride = (width_byte + 6) // 7
        if not width_byte or not height or len(record) != 2 + height * stride:
            raise ValueError(f"D glyph {index}: invalid dimensions or length")
        rows = []
        for row in range(height):
            chunk = record[2 + row * stride:2 + (row + 1) * stride]
            rows.append("".join("#" if byte & (1 << bit) else "."
                                for byte in chunk for bit in range(8)))
        code = index + 0x20
        glyphs.append({"code": code,
                       "character": chr(code) if code <= 0x7E else None,
                       "width_byte": width_byte, "height": height,
                       "rows": rows})
    return {"glyphs": glyphs}


def encode_d(source):
    glyphs = source["glyphs"]
    if len(glyphs) != GLYPH_COUNT:
        raise ValueError("Expected 107 D glyphs")
    payload = bytearray()
    pointers = []
    for index, glyph in enumerate(glyphs):
        if glyph["code"] != index + 0x20:
            raise ValueError(f"D glyph {index}: code is out of order")
        width_byte, height = glyph["width_byte"], glyph["height"]
        if not 1 <= width_byte <= 255 or not 1 <= height <= 255:
            raise ValueError(f"D glyph {index}: invalid dimensions")
        stride = (width_byte + 6) // 7
        if len(glyph["rows"]) != height:
            raise ValueError(f"D glyph {index}: wrong row count")
        pointers.append(BASE + DATA_START + len(payload))
        payload.extend((width_byte, height))
        for row in glyph["rows"]:
            if len(row) != stride * 8 or set(row) - {"#", "."}:
                raise ValueError(f"D glyph {index}: invalid bitmap row")
            for start in range(0, len(row), 8):
                payload.append(sum(1 << bit for bit, pixel in enumerate(row[start:start + 8])
                                   if pixel == "#"))
    pointers.extend([0] * (POINTER_COUNT - GLYPH_COUNT))
    return (bytes(pointer & 0xFF for pointer in pointers)
            + bytes(pointer >> 8 for pointer in pointers) + payload)
