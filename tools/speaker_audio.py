"""Render N/R speaker players from their original 6502 instruction bytes.

This interpreter deliberately supports only the instructions used by these
players and their delay routine. An unexpected opcode fails extraction rather
than substituting an estimated note frequency. Interrupts and decimal mode are
disabled. WAVs model a 1 MHz CPU and a simple 50 Hz speaker high-pass filter;
they are listening previews, not recordings of a particular Apple II speaker.
"""

import array
import io
import math
import sys
import wave


CPU_HZ = 1_000_000
SAMPLE_RATE = 44_100


class SpeakerPlayer:
    def __init__(self, data, entry, track):
        self.memory = bytearray(65536)
        self.memory[0x6000:0x6000 + len(data)] = data
        self.memory[0x18] = 1  # sound enabled
        self.a, self.x, self.y = track, 0, 0
        self.c = self.n = self.z = 0
        self.sp = 0xFF
        self.pc = entry
        self.cycles = 0
        self.toggles = []
        self.push(0xFF)
        self.push(0xFE)  # top-level RTS returns to the $FFFF sentinel

    def push(self, value):
        self.memory[0x100 + self.sp] = value
        self.sp = (self.sp - 1) & 255

    def pop(self):
        self.sp = (self.sp + 1) & 255
        return self.memory[0x100 + self.sp]

    def fetch(self):
        value = self.memory[self.pc]
        self.pc = (self.pc + 1) & 65535
        return value

    def word(self):
        return self.fetch() | self.fetch() << 8

    def nz(self, value):
        self.z, self.n = int(value == 0), int(bool(value & 128))
        return value

    def branch(self, condition):
        offset = self.fetch()
        cycles = 2
        if condition:
            target = (self.pc + (offset if offset < 128 else offset - 256)) & 65535
            cycles += 1 + int((target ^ self.pc) & 0xFF00 != 0)
            self.pc = target
        return cycles

    def run(self):
        while self.pc != 0xFFFF:
            if self.cycles > 250_000_000:
                raise ValueError("speaker player did not return within the cycle limit")
            address = self.pc
            opcode = self.fetch()
            if opcode in (0xA9, 0xA2):  # LDA/LDX immediate
                value = self.nz(self.fetch())
                if opcode == 0xA9:
                    self.a = value
                else:
                    self.x = value
                cycles = 2
            elif opcode in (0xA5, 0xA6, 0xA4):  # LDA/LDX/LDY zero page
                value = self.nz(self.memory[self.fetch()])
                if opcode == 0xA5:
                    self.a = value
                elif opcode == 0xA6:
                    self.x = value
                else:
                    self.y = value
                cycles = 3
            elif opcode in (0xAD, 0xBD):  # LDA absolute / absolute,X
                base = self.word()
                target = (base + (self.x if opcode == 0xBD else 0)) & 65535
                cycles = 4 + int(opcode == 0xBD and (base ^ target) & 0xFF00 != 0)
                self.a = self.nz(self.memory[target])
                if target == 0xC030:
                    self.toggles.append(self.cycles + cycles)
            elif opcode == 0xB1:  # LDA (zero page),Y
                zp = self.fetch()
                base = self.memory[zp] | self.memory[(zp + 1) & 255] << 8
                target = (base + self.y) & 65535
                self.a = self.nz(self.memory[target])
                cycles = 5 + int((base ^ target) & 0xFF00 != 0)
            elif opcode in (0x85, 0x8D):  # STA zero page / absolute (self-modifying)
                target = self.fetch() if opcode == 0x85 else self.word()
                self.memory[target] = self.a
                cycles = 3 if opcode == 0x85 else 4
            elif opcode in (0xE6, 0xC6, 0x46):  # INC/DEC/LSR zero page
                target = self.fetch()
                value = self.memory[target]
                if opcode == 0x46:
                    self.c = value & 1
                    value >>= 1
                else:
                    value = (value + (1 if opcode == 0xE6 else -1)) & 255
                self.memory[target] = self.nz(value)
                cycles = 5
            elif opcode in (0xC9, 0xE9):  # CMP/SBC immediate; binary arithmetic
                value = self.fetch()
                result = self.a - value - (1 - self.c if opcode == 0xE9 else 0)
                self.c = int(result >= 0)
                result = self.nz(result & 255)
                if opcode == 0xE9:
                    self.a = result
                cycles = 2
            elif opcode == 0x29:  # AND immediate
                self.a = self.nz(self.a & self.fetch())
                cycles = 2
            elif opcode == 0x0A:  # ASL accumulator
                self.c = self.a >> 7
                self.a = self.nz((self.a << 1) & 255)
                cycles = 2
            elif opcode == 0xAA:  # TAX
                self.x = self.nz(self.a)
                cycles = 2
            elif opcode == 0xCA:  # DEX
                self.x = self.nz((self.x - 1) & 255)
                cycles = 2
            elif opcode == 0x38:  # SEC
                self.c = 1
                cycles = 2
            elif opcode in (0xF0, 0xD0, 0x10):
                cycles = self.branch(self.z if opcode == 0xF0 else
                                     not self.z if opcode == 0xD0 else not self.n)
            elif opcode == 0x4C:  # JMP absolute
                self.pc = self.word()
                cycles = 3
            elif opcode == 0x20:  # JSR
                target = self.word()
                return_address = (self.pc - 1) & 65535
                self.push(return_address >> 8)
                self.push(return_address & 255)
                self.pc = target
                cycles = 6
            elif opcode == 0x60:  # RTS
                self.pc = ((self.pop() | self.pop() << 8) + 1) & 65535
                cycles = 6
            elif opcode == 0x48:  # PHA
                self.push(self.a)
                cycles = 3
            elif opcode == 0x68:  # PLA
                self.a = self.nz(self.pop())
                cycles = 4
            else:
                raise ValueError(f"unsupported speaker opcode ${opcode:02X} at ${address:04X}")
            self.cycles += cycles
        return self.cycles, self.toggles


def render_track(data, entry, track):
    cycles, toggles = SpeakerPlayer(data, entry, track).run()
    samples = array.array("h")
    count = math.ceil(cycles * SAMPLE_RATE / CPU_HZ)
    event = 0
    level = -1.0
    previous = level
    filtered = 0.0
    decay = math.exp(-2 * math.pi * 50 / SAMPLE_RATE)
    for index in range(count):
        while event < len(toggles) and toggles[event] * SAMPLE_RATE <= index * CPU_HZ:
            level = -level
            event += 1
        filtered = decay * (filtered + level - previous)
        previous = level
        samples.append(max(-32767, min(32767, round(filtered * 12000))))
    if sys.byteorder != "little":
        samples.byteswap()
    output = io.BytesIO()
    with wave.open(output, "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(SAMPLE_RATE)
        audio.writeframes(samples.tobytes())
    return output.getvalue(), {"id": track, "cpu_cycles": cycles,
                              "speaker_toggles": len(toggles),
                              "duration_seconds": cycles / CPU_HZ}


def sound_previews(data, module, variant, view, directory):
    from n_sounds import SOUND_TABLE_ADDRESS
    table = SOUND_TABLE_ADDRESS[variant] if module == "N" else 0x62CB
    entry = table - 0x7E
    if data[entry - 0x6000:entry - 0x6000 + 2] != bytes((0xA6, 0x18)):
        raise ValueError(f"{variant}/{module}: speaker player entry changed")
    tracks = []
    for track in view["tracks"]:
        filename = f"{module}-sound-{track['id']:02d}.wav"
        wav, info = render_track(data, entry, track["id"])
        (directory / filename).write_bytes(wav)
        tracks.append({**info, "file": filename})
    return {"cpu_hz": CPU_HZ, "sample_rate": SAMPLE_RATE,
            "speaker_model": "toggle level with 50 Hz high-pass filter",
            "interrupts": False, "tracks": tracks}
