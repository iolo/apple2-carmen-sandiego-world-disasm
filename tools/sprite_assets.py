"""Lossless codec for the variable-size bitmap records in T and U."""


def decode_sprites(data):
    sprites = []
    offset = 0
    while offset < len(data):
        if offset + 2 > len(data):
            raise ValueError(f"Truncated sprite header at {offset}")
        width, height = data[offset:offset + 2]
        if not width or not height:
            raise ValueError(f"Invalid sprite dimensions at {offset}")
        stride = (width + 6) // 7
        end = offset + 2 + stride * height
        if end > len(data):
            raise ValueError(f"Truncated sprite at {offset}")
        rows = []
        for row in range(height):
            chunk = data[offset + 2 + row * stride:offset + 2 + (row + 1) * stride]
            rows.append("".join("#" if byte & (1 << bit) else "."
                                for byte in chunk for bit in range(8)))
        sprites.append({"number": len(sprites), "file_offset": offset,
                        "width": width, "height": height, "rows": rows})
        offset = end
    return {"sprites": sprites}


def encode_sprites(source):
    output = bytearray()
    for number, sprite in enumerate(source["sprites"]):
        width, height = sprite["width"], sprite["height"]
        if sprite["number"] != number or sprite["file_offset"] != len(output):
            raise ValueError(f"Sprite {number}: incorrect order or offset")
        if not 1 <= width <= 255 or not 1 <= height <= 255:
            raise ValueError(f"Sprite {number}: invalid dimensions")
        stride = (width + 6) // 7
        if len(sprite["rows"]) != height:
            raise ValueError(f"Sprite {number}: wrong row count")
        output.extend((width, height))
        for row in sprite["rows"]:
            if len(row) != stride * 8 or set(row) - {"#", "."}:
                raise ValueError(f"Sprite {number}: invalid bitmap row")
            for start in range(0, len(row), 8):
                output.append(sum(1 << bit for bit, pixel in enumerate(row[start:start + 8])
                                  if pixel == "#"))
    return bytes(output)
