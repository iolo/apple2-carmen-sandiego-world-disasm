# MAME Lua autoplay

[`tools/korean/autoplay.lua`](../../tools/korean/autoplay.lua) plays the approved
Korean 800K edition with a memory-assisted strategy. It reads the culprit,
trait matrix, planned route, and final hideout markers, then selects the
native menus to obtain a warrant, fly to each destination, and arrest the
suspect. This is an assisted demonstration, not a solver that reads the
Korean clues or deduces the suspect from witness reports.

From the repository root:

```sh
python3 -m tools.korean.mame --session carmen-player --autoplay --visible
```

The default image is `build/korean/approved/carmen-world-ko.po`. The launcher
copies it to `build/korean/carmen-player/carmen-world.hdv` before mounting it;
all detective progress and Hall of Fame writes go to that copy. Choose a new
session name for every launch. The `.hdv` suffix lets MAME mount this raw
800K ProDOS image through the CFFA hard-disk interface.

The default detective is `LUASLEUTH`. A fresh detective completes 29 ordinary
cases before the game selects Carmen for case 30. The player stops after her
retirement is saved and the Hall of Fame is displayed. Otherwise, the default
limit is 30 successful arrests. Existing detective progress on a supplied copy
can shorten the run.

## Options

```sh
# One arrest and promotion, headless, then exit MAME:
python3 -m tools.korean.mame --session carmen-smoke --autoplay --case-limit 1 --exit-on-done

# Full headless run, then exit:
python3 -m tools.korean.mame --session carmen-full --autoplay --exit-on-done

# Watch at original machine speed (default is fast-forward):
python3 -m tools.korean.mame --session carmen-watch --autoplay --visible --throttle

# Start from the progress saved by an earlier run, using a new copy:
python3 -m tools.korean.mame --session carmen-continue --autoplay \
  --image build/korean/carmen-smoke/carmen-world.hdv --detective LUASLEUTH
```

`--detective NAME` accepts 1–15 ASCII letters. The game's additional pixel-width
limit still applies; use a short name. Registration, any saved-case prompt,
and next-case prompts are answered Yes. A full detective roster or a rejected
name causes the run to stop with an error rather than delete existing records.
Without `--exit-on-done`, MAME remains stopped in the debugger at completion.
The player removes its own breakpoints and keyboard tap, so you can resume
manually. During a run, stop the player with:

```sh
python3 -m tools.korean.mame_rpc --session carmen-player \
  --lua 'carmen_player.stop(); return carmen_player.result'
```

## Prerequisites and mechanism

Tested with MAME 0.285 on Linux, `apple2e`, 64K main RAM plus the `ext80` 64K
auxiliary card, CFFA202, and its 6502 firmware. The launcher verifies local
ROMs. Override its machine ROM directory with `--rompath PATH` and CFFA
firmware file with `--cffa-rom PATH`. See `python3 -m tools.korean.mame --help`
for the local defaults. Build the approved image and symbol maps with
`make korean` if they are absent. The existing mailbox bootstrap also requires
the a2-mame skill's `control.lua`; its path can be overridden with
`CARMEN_MAME_CONTROL`. Visible mode needs an available SDL/Qt display.

The Lua script runs through the existing mailbox startup hook. It uses
[MAME debugger breakpoints](https://docs.mamedev.org/luascript/ref-debugger.html)
to identify native input routines, and a one-shot
[memory read tap](https://docs.mamedev.org/luascript/ref-mem.html) to supply a
keyboard-latch byte at `$C000`. Input is emulated at the keyboard-register
level rather than posted as a held host key. It never writes game RAM or CPU
registers, patches instructions, seeds a case, or changes the clock or rank.
Menus, travel costs, warrant matching, animations, promotion, and saving all
execute in the game itself. Breakpoints are switched when the overlapping
R intro and N gameplay modules are loaded. Native keyboard opcodes are checked
against the generated symbol map before play.

Only this repository's 800K build and matching symbol maps are supported.
Random routes can vary. A native timeout, unexpected menu/debugger state,
incorrect warrant, or 180 seconds without progress produces an error receipt.
MAME's process exit code alone is not a success verdict: inspect the receipt.

## Results

Each session directory contains:

- `autoplay.jsonl`: case, city, warrant, arrest, promotion/save, and retirement events.
- `autoplay-result.json`: `carmen-arrested`, `case-limit`, `stopped`, or `error`,
  plus the native final state and run counters.
- `autoplay-final.png` and `autoplay-final.hgr`: final video snapshot and exact
  displayed HGR bytes. A paused PNG can precede the last rendered frame.
- `session.json`: launch command and source-image SHA-256.
- `carmen-world.hdv`: writable disk copy containing the game's own saves.
- `mame.log`: emulator and player diagnostics.

A successful full run has `result: "carmen-arrested"`, `hall_of_fame: true`,
`state.suspect: 0`, `state.warrant: 0`, and `state.rank: 5`. Starting fresh,
`arrests` and `state.solved` are both 30. A case-limit stop occurs after the
native progress save; it does not save an in-progress H case snapshot.

Verified on 2026-10-19: a fresh `LUASLEUTH` completed all 30 cases, reached
rank 5, and appeared in the saved Hall of Fame in 59 seconds of headless
fast-forward. The native retirement removed its roster entry. Only G differed
from the source image at completion; F returned to its original contents.
The input image remained unchanged. A visible one-case run and a new process
continuing the saved detective from one to two solved cases also passed.
The [verification receipt](runtime/autoplay.json) records the exact input-image
and script hashes, all 30 case starts, final state, and disk checks.
