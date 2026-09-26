"""Decode speaker sequences embedded in the N and R overlays."""


LOAD_ADDRESS = 0x6000
PERIOD_COUNT = 33
SOUND_TABLE_ADDRESS = {"disk1": 0x8A85, "po": 0x8A89}


def decode_n_sounds(data, variant):
    return _decode_sounds(data, variant, "N", SOUND_TABLE_ADDRESS[variant], 12)


def decode_r_sounds(data, variant):
    return _decode_sounds(data, variant, "R", 0x62CB, 2)


def _decode_sounds(data, variant, module, table_address, track_count):
    start = table_address - LOAD_ADDRESS
    periods = list(data[start:start + PERIOD_COUNT])
    if len(periods) != PERIOD_COUNT or periods[0] != 0 or any(
            periods[i] >= periods[i + 1] for i in range(1, PERIOD_COUNT - 1)):
        raise ValueError(f"{variant}/{module}: unexpected speaker period table")
    pointer_start = start + PERIOD_COUNT
    pointers = [int.from_bytes(data[pointer_start + i * 2:pointer_start + i * 2 + 2],
                               "little") for i in range(track_count)]
    data_start = LOAD_ADDRESS + pointer_start + track_count * 2
    if pointers[0] != data_start or len(set(pointers)) != track_count:
        raise ValueError(f"{variant}/{module}: unexpected sound pointers")
    tracks = []
    ranges = []
    for track_id, pointer in enumerate(pointers):
        offset = pointer - LOAD_ADDRESS
        if not 0 <= offset < len(data):
            raise ValueError(f"{variant}/{module}: sound pointer outside module")
        commands = []
        cursor = offset
        while True:
            if cursor >= len(data):
                raise ValueError(f"{variant}/{module}: unterminated sound {track_id}")
            value = data[cursor]
            cursor += 1
            if value == 0xFF:
                break
            if value >= 0x80:
                commands.append({"duration": value & 0x7F})
            elif value < PERIOD_COUNT:
                commands.append({"note": value, "period": periods[value]})
            else:
                raise ValueError(f"{variant}/{module}: invalid sound note {value}")
        ranges.append((offset, cursor))
        tracks.append({"id": track_id, "address": pointer, "commands": commands})
    ordered = sorted(ranges)
    if ordered[0][0] != data_start - LOAD_ADDRESS or any(
            first[1] != second[0] for first, second in zip(ordered, ordered[1:])):
        raise ValueError(f"{variant}/{module}: sound streams are not contiguous")
    return {"periods": periods, "default_duration": 20, "tracks": tracks}
