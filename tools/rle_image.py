"""Decode the HGR run-length image format used by R's $69BE routine."""

from s2_image_codec import decode_stream, encode_stream


N_PICTURE_TABLE = {"disk1": 0x8B97, "po": 0x8B9B}


def n_picture_records(n_data, variant):
    """Read N's six parallel geometry/pointer tables for pictures 0-5."""
    start = N_PICTURE_TABLE[variant] - 0x6000
    raw = n_data[start:start + 42]
    if len(raw) != 42:
        raise ValueError(f"{variant}/N: truncated picture metadata")
    stride, lows, highs, y0s, y1s, x0s, x1s = (
        raw[i:i + 6] for i in range(0, 42, 6))
    records = []
    for number in range(6):
        pointer = lows[number] | (highs[number] << 8)
        records.append({"number": number, "loaded_address": pointer,
                        "x_start": x0s[number], "x_end": x1s[number],
                        "y_start": y0s[number], "y_end": y1s[number],
                        "scanline_stride": stride[number]})
    return records


def hgr_offset(y, x):
    return (((y & 7) << 10) | (((y >> 3) & 7) << 7) | ((y >> 6) * 40)) + x


def decode_image(data, start):
    """Return (header, 8 KiB HGR page, first byte after the compressed record).

    The six-byte header is x0, x1, y0, y1, marker, scanline stride.
    Bytes are stored by column, then scanline. A marker is followed by a
    value and a repeat count; count zero represents 256 copies. Stride two
    stores even and odd scanlines in separate passes.
    """
    if start + 6 > len(data):
        raise ValueError("Truncated RLE image header")
    x0, x1, y0, y1, marker, stride = data[start:start + 6]
    header, page, cursor = _decode_pixels(data, start + 6, x0, x1, y0, y1,
                                           marker, stride)
    return header, page, cursor


def decode_s_source(chunk, number, loaded_address):
    """Expose one fixed-size S record as editable RLE commands."""
    header, _, consumed = decode_image(chunk, 0)
    if any(chunk[consumed:]):
        raise ValueError(f"S image {number}: nonzero bytes after compressed stream")
    stream = decode_stream(bytes((header["scanline_stride"], header["marker"]))
                           + chunk[6:consumed])
    if encode_stream(stream)[2:] != chunk[6:consumed]:
        raise ValueError(f"S image {number}: compressed commands do not round trip")
    return {"number": number, "loaded_address": loaded_address,
            "capacity": len(chunk),
            "x_start": header["x_start"], "x_end": header["x_end"],
            "y_start": header["y_start"], "y_end": header["y_end"],
            **stream}


def encode_s_source(source, number, loaded_address, capacity):
    """Build one S record and fill its fixed-address remainder with zeros."""
    if (source["number"] != number or source["loaded_address"] != loaded_address
            or source["capacity"] != capacity):
        raise ValueError(f"S image {number}: record position or capacity changed")
    header = bytes(source[key] for key in
                   ("x_start", "x_end", "y_start", "y_end", "marker",
                    "scanline_stride"))
    stream = encode_stream(source)
    chunk = header + stream[2:]
    if len(chunk) > capacity:
        raise ValueError(f"S image {number}: compressed data exceeds {capacity} bytes")
    _, _, consumed = decode_image(chunk, 0)
    if consumed != len(chunk):
        raise ValueError(f"S image {number}: unused compressed commands")
    return chunk.ljust(capacity, b"\0")


def decode_o_source(chunk, item):
    """Expose an O record whose geometry is stored in N."""
    header, _, consumed = decode_external_image(
        chunk, 0, item["x_start"], item["x_end"], item["y_start"],
        item["y_end"], item["scanline_stride"])
    if any(chunk[consumed:]):
        raise ValueError(f"O image {item['number']}: nonzero padding")
    stream = decode_stream(bytes((item["scanline_stride"], header["marker"]))
                           + chunk[1:consumed])
    if encode_stream(stream)[2:] != chunk[1:consumed]:
        raise ValueError(f"O image {item['number']}: commands do not round trip")
    return {"number": item["number"], "loaded_address": item["loaded_address"],
            "capacity": len(chunk),
            "x_start": item["x_start"], "x_end": item["x_end"],
            "y_start": item["y_start"], "y_end": item["y_end"],
            **stream}


def encode_o_source(source, item, capacity):
    """Build an O record without changing the N-owned geometry or its address."""
    for key in ("number", "loaded_address", "x_start", "x_end", "y_start",
                "y_end", "scanline_stride"):
        if source[key] != item[key]:
            raise ValueError(f"O image {item['number']}: N field {key} changed")
    if source["capacity"] != capacity:
        raise ValueError(f"O image {item['number']}: capacity changed")
    stream = encode_stream(source)
    chunk = bytes((source["marker"],)) + stream[2:]
    if len(chunk) > capacity:
        raise ValueError(f"O image {item['number']}: compressed data exceeds {capacity} bytes")
    _, _, consumed = decode_external_image(
        chunk, 0, item["x_start"], item["x_end"], item["y_start"],
        item["y_end"], item["scanline_stride"])
    if consumed != len(chunk):
        raise ValueError(f"O image {item['number']}: unused compressed commands")
    return chunk.ljust(capacity, b"\0")


def decode_p_source(data, records):
    """Expose P's shared prefix and the complete picture-5 RLE stream."""
    if len(data) != 1060:
        raise ValueError("P must contain 1060 bytes")
    first, fifth = records[0], records[5]
    if first["loaded_address"] != 0x1101 or fifth["loaded_address"] != 0x1105:
        raise ValueError("Unexpected P picture pointers in N")
    _, _, first_end = decode_external_image(
        data, 1, first["x_start"], first["x_end"], first["y_start"],
        first["y_end"], data[0])
    _, _, fifth_end = decode_external_image(
        data, 5, fifth["x_start"], fifth["x_end"], fifth["y_start"],
        fifth["y_end"], fifth["scanline_stride"])
    if first_end > fifth_end or any(data[fifth_end:]):
        raise ValueError("P has data after picture 5 or picture 0 extends past it")
    stream = decode_stream(bytes((fifth["scanline_stride"], data[5]))
                           + data[6:fifth_end])
    if encode_stream(stream)[2:] != data[6:fifth_end]:
        raise ValueError("P picture 5 commands do not round trip")
    return {"file_size": len(data),
            "picture_0": {"loaded_address": first["loaded_address"],
                          "scanline_stride": data[0], "marker": data[1],
                          "initial_body_hex": data[2:5].hex()},
            "picture_5": {"loaded_address": fifth["loaded_address"],
                          **stream}}


def encode_p_source(source, records):
    """Build P and verify that both overlapping pictures still decode."""
    first, fifth = records[0], records[5]
    picture_0, picture_5 = source["picture_0"], source["picture_5"]
    if (source["file_size"] != 1060
            or picture_0["loaded_address"] != first["loaded_address"]
            or picture_5["loaded_address"] != fifth["loaded_address"]
            or picture_5["scanline_stride"] != fifth["scanline_stride"]):
        raise ValueError("P size, address, or N-owned stride changed")
    initial = bytes.fromhex(picture_0["initial_body_hex"])
    if len(initial) != 3 or not 1 <= picture_0["scanline_stride"] <= 255:
        raise ValueError("Invalid P picture-0 prefix")
    stream = encode_stream(picture_5)
    data = bytes((picture_0["scanline_stride"], picture_0["marker"]))
    data += initial + stream[1:]
    if len(data) > source["file_size"]:
        raise ValueError("P compressed stream exceeds fixed file size")
    complete = data.ljust(source["file_size"], b"\0")
    _, _, first_end = decode_external_image(
        complete, 1, first["x_start"], first["x_end"], first["y_start"],
        first["y_end"], picture_0["scanline_stride"])
    _, _, fifth_end = decode_external_image(
        complete, 5, fifth["x_start"], fifth["x_end"], fifth["y_start"],
        fifth["y_end"], fifth["scanline_stride"])
    if first_end > len(data) or fifth_end != len(data):
        raise ValueError("P pictures do not consume the edited compressed stream")
    return complete


def decode_external_image(data, start, x0, x1, y0, y1, stride,
                          allow_short_tail=False):
    """Decode an N image whose geometry comes from its six parallel tables."""
    if start >= len(data):
        raise ValueError("Truncated external-header RLE image")
    return _decode_pixels(data, start + 1, x0, x1, y0, y1,
                          data[start], stride, allow_short_tail)


def _decode_pixels(data, cursor, x0, x1, y0, y1, marker, stride,
                   allow_short_tail=False):
    if not (0 <= x0 <= x1 < 40 and 0 <= y0 <= y1 < 192 and 1 <= stride <= 255):
        raise ValueError("Invalid RLE image geometry")
    page = bytearray(b"\x80" * 8192)
    leftover = 0
    value = 0
    missing_pixels = 0
    for phase in range(1 if stride == 1 else 2):
        for x in range(x0, x1 + 1):
            for y in range(y0 + phase, y1 + 1, stride):
                if not leftover:
                    if cursor >= len(data):
                        if not allow_short_tail:
                            raise ValueError(f"Truncated RLE image data at x={x}, "
                                             f"y={y}, phase={phase}")
                        value = 0x80
                        leftover = 1
                        missing_pixels += 1
                    else:
                        value = data[cursor]
                        cursor += 1
                        if value == marker:
                            if cursor + 2 > len(data):
                                raise ValueError("Truncated RLE run")
                            value = data[cursor]
                            leftover = data[cursor + 1] or 256
                            cursor += 2
                        else:
                            leftover = 1
                page[hgr_offset(y, x)] = value
                leftover -= 1
    header = {"x_start": x0, "x_end": x1, "y_start": y0, "y_end": y1,
              "marker": marker, "scanline_stride": stride,
              "unused_copies_in_final_run": leftover,
              "missing_pixels_at_eof": missing_pixels}
    return header, bytes(page), cursor
