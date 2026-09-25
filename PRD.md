# apple2-carmen-sandiego-world-disasm

## GOAL

Reverse the Apple II game "Where in the World is Carmen Sandiego?" for educational purposes. The goal is to produce a
human-readable disassembled source code, extract assets, and provide a build script to generate a disk image from the
disassembled source code and extracted assets.

## Source

- carmen-world-disk1.dsk
- carmen-world-disk2.dsk
- carmen-world.po (prodos 800K version)
- carmen-world.pdf (without text)
- carmen-world-gs.pdf (Apple IIgs version with text)

## Output

- human readable disassembled source code
- extracted assets(texts, images, sounds, etc.)
- build script to generate an (possibly) identical disk image from the disassembled source code and extracted assets

## Tools

- Cross assembler/disassembler for 6502
  - ca65/cl65 (part of cc65)
- Apple II emulator as you prefer
  - MAME with Apple II driver and lua scripting.
  - Apple2ts with Apple2ts-server mcp server
- Disk image tools(as you prefer)
  - a2kit
  - AppleCommander
- Python, Node or other scripting language as you prefer for automation and asset extraction.

## References

- My earlier disassembly projects for Apple II games
  - https://github.com/iolo/apple2-stella7-disasm
  - https://github.com/iolo/apple2-rescue-raiders-disasm
  - https://github.com/iolo/apple2-sundog-disasm


