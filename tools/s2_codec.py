"""Lossless word-token markup for the text portion of S2 records."""

import re


TOKEN = re.compile(r"\{([^{}]+)\}")


def c_dictionary(data):
    """Return the file offset and 128 words for S2 token bytes $80-$FF."""
    marker = b"a\0about\0address\0"
    start = data.find(marker)
    if start < 0 or data.find(marker, start + 1) >= 0:
        raise ValueError("Cannot locate the C word dictionary uniquely")
    words = data[start:].split(b"\0", 128)[:128]
    if len(words) != 128 or words[0] != b"a" or words[-1] != b"your":
        raise ValueError("Unexpected C word dictionary")
    if any(not word or any(byte < 32 or byte > 126 for byte in word) for word in words):
        raise ValueError("Non-ASCII C dictionary word")
    decoded = [word.decode("ascii") for word in words]
    if len(set(decoded)) != 128:
        raise ValueError("Repeated C dictionary word")
    return start, decoded


def markup_line(data, words):
    result = []
    for byte in data:
        if byte >= 128:
            result.append("{" + words[byte - 128] + "}")
        elif 32 <= byte <= 126 and byte not in (ord("{"), ord("}")):
            result.append(chr(byte))
        else:
            raise ValueError(f"Unexpected S2 text byte ${byte:02X}")
    return "".join(result)


def encode_line(markup, words):
    codes = {word: 128 + index for index, word in enumerate(words)}
    result = bytearray()
    position = 0
    for match in TOKEN.finditer(markup):
        literal = markup[position:match.start()]
        if "{" in literal or "}" in literal:
            raise ValueError("Unmatched brace in S2 text")
        result.extend(literal.encode("ascii"))
        word = match.group(1)
        if word not in codes:
            raise ValueError(f"Unknown S2 dictionary word: {word}")
        result.append(codes[word])
        position = match.end()
    literal = markup[position:]
    if "{" in literal or "}" in literal:
        raise ValueError("Unmatched brace in S2 text")
    result.extend(literal.encode("ascii"))
    if any(byte < 32 or byte > 126 for byte in result if byte < 128):
        raise ValueError("S2 literal text must be printable ASCII")
    return bytes(result)
