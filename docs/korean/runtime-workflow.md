# Runtime testing and Lua control

Start with `make korean` and `make korean-image-check`. The recorded checks
are indexed in [runtime/README.md](runtime/README.md); their scope and visual
results are in [release-checks.md](release-checks.md).

## Reproduce the approved tests

MAME 0.285, local Apple //e ROMs, CFFA 6502 firmware and the `a2-mame` skill's
`control.lua` are prerequisites. `tools/korean/mame.py --help` lists the ROM
options; `CARMEN_MAME_CONTROL` can select another helper location. The launcher
uses `apple2e`, 64K main RAM, an ext80 card with 64K auxiliary RAM and copied
writable media. It isolates configuration, NVRAM and snapshots and does not
download ROMs.

Use new session names and tags for each run. Run the lifecycle suite before
the save-transfer suite, which uses its disposable saved disk:

```sh
python3 -m tools.korean.synthetic_test --mode approved --session NEW-life --fresh-session NEW-restore --name KOREAN
python3 -m tools.korean.reader_test --mode approved --session NEW-readers
python3 -m tools.korean.clock_test --mode approved --session NEW-clock
python3 -m tools.korean.caption_test --mode approved --session NEW-captions
python3 -m tools.korean.message_test --mode approved --session NEW-messages
python3 -m tools.korean.city_test --mode approved --session NEW-cities
python3 -m tools.korean.gameplay_test --tag NEW-gameplay
python3 -m tools.korean.save_compat_test --tag NEW-cross
python3 -m tools.korean.disk_error_test --tag NEW-errors
python3 -m tools.korean.visual_test --tag NEW-visual
```

The six component/lifecycle suites accept `--mode synthetic|approved`, with
`synthetic` as the default. Approved mode uses literal catalog text and separate
fixtures/reports under `runtime/approved/`. Synthetic mode uses an equal-size
bijection of Hangul cells for preapproval feasibility.

The gameplay runner cold-restores native-generated rank 0/1/4 route fixtures
and uses menu input for traits, warrants, animations and reports. Its resumable
progress reports pin completed pairs to the exact image. The save-transfer
runner imports whole F/G/H sets into owned unmounted copies. Disk-error tests
remove R or H from a disposable disk, observe the actual ProDOS prompt, mount
an owned good disk and acknowledge native retry. No mounted host file or game
instruction is patched.

Open Apple speeds text and also acts as a confirmation button. The runners
allow its release and the natural-keyboard queue to finish between actions.
Temporary read taps suppress stale host input only during that idle interval;
they are removed before the tested action. Physical arrow taps also include
a released-key interval.

## Execute a Lua command

The default transport is a local file-mailbox plugin; it works while paused
and at debugger stops, without stdin or a network listener:

```sh
python3 -m tools.korean.mame --session NEW-debug --image build/korean/approved/carmen-world-ko.po
python3 -m tools.korean.mame_rpc --session NEW-debug --call status
python3 -m tools.korean.mame_rpc --session NEW-debug --lua 'return a2.registers()'
python3 -m tools.korean.mame_rpc --session NEW-debug --call breakpoint --args '[24604]'
python3 -m tools.korean.mame_rpc --session NEW-debug --call go
```

`--lua` executes a line and returns its result in a JSON receipt. `--call`
invokes an `a2` helper with structured positional arguments. The session's
`mailbox/` records unique request/response IDs; `mame.log` holds diagnostics
and `session.json` records the owned PID, image hash and exact machine command.
The optional `--console` flag enables the legacy stdin console.

Requests use atomic renames and a single-client lock. Do not send another
client command while a suite controls that session. A timed-out mutation must
be inspected before retrying; a scheduled `go`, save, restore or exit receipt
requires subsequent state verification. Use a fresh `status` call rather than
a ready file to check liveness.

## Debugger and save checks

R and N overlay the same addresses. Stop at `$601C` after R initialization or
`$6000` after handoff, and verify the complete resident module before using its
symbols. Change CPU registers only at a debugger instruction boundary; an
ordinary pause may stop between 6502 bus cycles.

`korean_checkpoint(name)` records CPU registers, mapping, case/menu state and
a PNG. `korean_memory_survey(name)` additionally captures main/aux RAM and the
active LC bank while preserving RAMRD. Interpret dumps using the recorded bank
mapping. A data-read tap is not proof of instruction fetches because the CPU
can use its opcode cache; debugger reads with side effects disabled are excluded.

Save through Visit Interpol → Save Case, capture state at `N_SAVE_CURRENT_CASE`,
and exit after sign-in returns. Cold-boot a new process with a copy of the saved
image, enter the same ASCII name and answer the actual resume prompt. Compare
all case bytes with the native menu/count resets, zero padding, consumed F
flag and unchanged unrelated files. [Save compatibility](save-compatibility.md)
documents the schema and transfer policy.

## Synthetic and earlier component experiments

```sh
make korean-synthetic
make korean-synthetic-check
# Run the same six suites without --mode approved, using new session names.
make korean-review
python3 -m tools.korean.native_test --session NEW-font
python3 -m tools.korean.renderer_test --session NEW-renderer
```

The font test poisons both font regions, runs the 6502 installer and checks every
fetched row through C2/C6, including page crossings and the 512-glyph bank split.
Renderer tests compare N/R HGR pages with independent font pixels and check the
narrow typewriter's complete glyph stream. Borrowed RAM, stack, registers,
module data and media are restored or verified unchanged.

The initial proxy probes (`make korean-probe`, `runtime.lua`) and full-font
residency experiments (`font_guard.lua`, `font_lifecycle.py`) are historical
K0/K4 tools, not prerequisites for normal approved builds. Their retained
reports and captures explain how the memory layout was established; consult
the modules' `--help` and [memory layout](memory-layout.md) when revisiting them.

## Audit or restore retained evidence

```sh
make korean-release-check
python3 -m tools.korean.evidence check
python3 -m tools.korean.evidence extract --archive runtime --output build/runtime-evidence
```

Auditors read loose captures first, then `runtime/artifacts.tar.xz`; the archive
index and report hashes are checked. Machine profiles remain verifiable after
temporary MAME session folders are removed. Extraction restores original paths
to a new directory. The current approved [review bundle](review/index.html)
stays immutable; older snapshots are in [review history](review/README.md).
