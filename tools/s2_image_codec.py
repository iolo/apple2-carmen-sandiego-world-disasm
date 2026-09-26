"""Lossless source format for compressed S2 city images."""


def decode_stream(data):
    if len(data) < 2:
        raise ValueError("S2 image lacks stride and marker")
    stride, marker = data[:2]
    if not 1 <= stride <= 2:
        raise ValueError("Unexpected S2 city-image scanline stride")
    segments = []
    literal = bytearray()
    cursor = 2
    while cursor < len(data):
        value = data[cursor]
        cursor += 1
        if value != marker:
            literal.append(value)
            continue
        if literal:
            segments.append({"literal_hex": literal.hex()})
            literal.clear()
        if cursor + 2 > len(data):
            raise ValueError("Truncated S2 city-image repeat")
        repeated = data[cursor]
        count_byte = data[cursor + 1]
        cursor += 2
        segments.append({"repeat_byte": repeated,
                         "count": count_byte or 256})
    if literal:
        segments.append({"literal_hex": literal.hex()})
    return {"scanline_stride": stride, "marker": marker,
            "segments": segments}


def encode_stream(source):
    stride, marker = source["scanline_stride"], source["marker"]
    if not 1 <= stride <= 2 or not 0 <= marker <= 255:
        raise ValueError("Invalid S2 city-image header")
    output = bytearray((stride, marker))
    for number, segment in enumerate(source["segments"]):
        if "literal_hex" in segment:
            literal = bytes.fromhex(segment["literal_hex"])
            if not literal or marker in literal:
                raise ValueError(f"S2 image segment {number}: invalid literal")
            output.extend(literal)
        else:
            value, count = segment["repeat_byte"], segment["count"]
            if not 0 <= value <= 255 or not 1 <= count <= 256:
                raise ValueError(f"S2 image segment {number}: invalid repeat")
            output.extend((marker, value, count & 0xFF))
    return bytes(output)
