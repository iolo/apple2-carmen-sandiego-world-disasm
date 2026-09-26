"""Editable view of the 800 KB N overlay's save-dialog message."""

LOAD = 0x6000
START = 0x86B1
END = 0x86ED
CONTROL_BYTES = {0x81, 0x82, 0x8D}


def decode_dialog(data):
    raw = data[START - LOAD:END - LOAD]
    if len(raw) != END - START or not raw.endswith(b"\0"):
        raise ValueError("N save dialog has an unexpected extent or terminator")
    segments = []
    printable = bytearray()
    for byte in raw[:-1]:
        if 32 <= byte <= 126:
            printable.append(byte)
            continue
        if printable:
            segments.append({"text": printable.decode("ascii")})
            printable.clear()
        if byte not in CONTROL_BYTES:
            raise ValueError(f"Unknown N save-dialog control ${byte:02X}")
        segments.append({"byte": byte})
    if printable:
        segments.append({"text": printable.decode("ascii")})
    source = {"load_address": START, "segments": segments}
    if encode_dialog(source) != raw:
        raise ValueError("N save dialog does not round trip")
    return source


def encode_dialog(source):
    if source["load_address"] != START:
        raise ValueError("N save dialog has the wrong load address")
    output = bytearray()
    for segment in source["segments"]:
        if set(segment) == {"text"}:
            encoded = segment["text"].encode("ascii")
            if not encoded or any(byte < 32 or byte > 126 for byte in encoded):
                raise ValueError("N save dialog contains nonprintable text")
            output.extend(encoded)
        elif set(segment) == {"byte"} and segment["byte"] in CONTROL_BYTES:
            output.append(segment["byte"])
        else:
            raise ValueError("N save dialog contains an invalid segment")
    output.append(0)
    if len(output) != END - START:
        raise ValueError("N save dialog must retain its original size")
    return bytes(output)
