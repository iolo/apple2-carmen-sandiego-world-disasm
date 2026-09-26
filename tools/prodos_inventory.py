"""Inspect flat ProDOS root directories without interpreting unused junk."""

import re


def root_inventory(read_block):
    first = read_block(2)
    if len(first) != 512 or first[4] >> 4 != 15:
        raise RuntimeError("Missing ProDOS volume-directory header")
    entry_size, entries_per_block = first[35], first[36]
    if (entry_size, entries_per_block) != (39, 13):
        raise RuntimeError("Unsupported ProDOS directory geometry")
    total_blocks = int.from_bytes(first[41:43], "little")
    declared = int.from_bytes(first[37:39], "little")
    volume = first[5:5 + (first[4] & 15)].decode("ascii")
    files, unused = [], []
    block, previous = 2, 0
    visited = set()
    while block:
        if block in visited or not 0 < block < total_blocks:
            raise RuntimeError("Invalid ProDOS root-directory chain")
        visited.add(block)
        data = first if block == 2 else read_block(block)
        if len(data) != 512 or int.from_bytes(data[:2], "little") != previous:
            raise RuntimeError("Invalid ProDOS directory backlink or block length")
        for slot in range(1 if block == 2 else 0, entries_per_block):
            entry = data[4 + slot * entry_size:4 + (slot + 1) * entry_size]
            storage = entry[0] >> 4
            if storage == 0:
                continue  # unused or deleted entry
            if storage not in (1, 2, 3, 4, 5, 13):
                unused.append({"block": block, "slot": slot,
                               "storage_byte": entry[0], "entry_hex": entry.hex()})
                continue
            name = entry[1:1 + (entry[0] & 15)].decode("ascii", errors="replace")
            if not re.fullmatch(r"[A-Z][A-Z0-9.]{0,14}", name) or name in files:
                raise RuntimeError(f"Invalid or duplicate ProDOS filename in block {block}, slot {slot}")
            files.append(name)
        previous, block = block, int.from_bytes(data[2:4], "little")
    if len(files) != declared:
        raise RuntimeError(f"ProDOS declares {declared} files but has {len(files)} valid entries")
    return {"volume": volume, "declared_file_count": declared,
            "files": files, "directory_blocks": sorted(visited),
            "malformed_unused_entries": unused}
