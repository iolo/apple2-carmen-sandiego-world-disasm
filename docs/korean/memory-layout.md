# Memory layout and capacity

The first sections record the original-game investigation; the integration
section records the final Korean allocations. Approved and synthetic text have
the same footprint. [Release checks](release-checks.md) cover the completed build.

Reproduce the measured file and disk report with `make korean-capacity`.
`original-capacity.json` verifies the original media and extracted-file hashes,
links original sources with debug symbols, and checks that each debug binary
still equals the original. Generated symbols are in `build/korean/maps/`.

The target is 64K main RAM plus the IIe extended 80-column card's 64K auxiliary
RAM. The original loader explicitly probes auxiliary memory and its own TEXT
MODE message requires 128K. No extra 64K is assumed to be free.

## Loaded files and reservations

Addresses below are half-open. Copy reservations include padding/stale bytes
that the loader copies beyond a file's EOF. Such bytes are not free by default.

| File/data | Actual placement or reservation | Evidence |
| --- | --- | --- |
| WORLD.SYSTEM | main `$2000–$2541`, boot only | SYS metadata and loader source |
| B | main `$9800–$9C72`, resident | `B_MODULE_BUFFER_PAGE` and public services |
| C | stage main `$6000`; copy 46 pages into aux `$2000–$4E00` | `BOOT_AUX_DEST_PAGES/PAGE_COUNTS` |
| C services | aux language card `$D200–$D400` | `BOOT_COPY_RESIDENT_C_BYTE`, ALTZP set |
| C lookup/text/icons | aux `$2200–$4E00` copied to aux LC `$D400–$10000` | C public copy entry `$D20C` |
| D | main `$B900–$BEC3`; next fixed region begins `$BF00` | font pointers and ProDOS MLI |
| E | main `$B200–$B900`, seven shift-table pages | loader module index 0 |
| I | aux `$6000–$7000`, 16-page boot copy; file 2,167 bytes | module index 8 and boot table |
| K | aux `$5000–$6000`, 16-page boot copy; file 1,275 bytes | module index 7 and boot table |
| J | aux `$7000–$7800`; selected graph main `$9F00` | C graph copy and loader |
| P | aux `$8000–$8500`, five-page copy | boot table; later picture-span copies |
| T | aux `$8500–$9400`, 15-page copy | intro and animation copy paths |
| U | aux `$9400–$A200`, 14-page copy | boot and arrest animation paths |
| R | main `$6000–$73E6`, intro overlay | R EOF and entry |
| S | main `$7800–$91C0`, intro compressed images | B module index 16; overlaps later N |
| N | main `$6000–$8EE0`, game overlay | B module index 12, N EOF |
| O | main `$A700–$B200`, game pictures | B module index 4 |
| S2 stored text | main `$A000`, at most 1,792 bytes before O | B READ parameters and O reservation |
| S2 image / H pages | main `$1100`, used at separate lifecycle points | B S2 READ / H load parameters |
| Selected description | main `$0E00–$0F00`, one page including NUL | `N_COPY_SELECTED_CITY_STRING_BYTE` |
| Selected route clues | main `$0F00`, append cursor and page carry | `N_PREPARE_CITY_CLUES`; 512-byte reservation; Korean maximum 190 bytes |
| Expanded report | main `$A000`, shares stored-S2 workspace | N/C append and expansion routines |
| F/G and case state | main `$0C00/$0D00`; active zero page in aux | runtime mapping receipts and loader |
| Display pages | main `$2000–$6000` | HGR page copy/render routines |
| ProDOS and I/O work | main/LC and loader buffers, preserved | MLI mapping and parameter blocks |

`$C003` enables auxiliary reads and `$C005` auxiliary writes. Some inherited
routine names/comments reverse that distinction; the opcodes and observed
mapping take precedence. ALTZP also selects the corresponding language-card
bank. Main and auxiliary addresses are not interchangeable capacity.

## Measurements and initial synthetic probe

The original 800K image has 1,186 free ProDOS blocks (607,232 bytes), measured
from its allocation bitmap. The rebuilt baseline has 1,206 free blocks
(617,472 bytes). Allocation/index/directory overhead still counts for new files.

The maximum original S2 stored-text region is 1,311 bytes (Tokyo, record 29).
The longest stored description including NUL is 154 bytes (New York,
record 17). The longest dictionary-expanded English line is 183 bytes. The
maximum three selected clues from distinct categories total 168 stored bytes,
including their NUL terminators.
These are English measurements, not Korean capacity approval.

The common main-RAM interval `$9200–$9800` is beyond the intro S reservation,
N overlay and before B. A 328-byte RAM-only synthetic probe fits there. It
temporarily redirects two D pointers to pinned GalmuriMono7 7×8 glyphs and
calls each original renderer, testing mixed `한글`/English text, a forced
break, wrapping and NUL termination. It restores the D pointers, zero page,
scratch RAM and CPU registers; it does not patch a disk image.

The Apple2TS watchpoint on this interval had no hit during the observed
briefing, city, investigation, travel and save sequence. MAME `apple2e`
with ext80 and CFFA 6502 firmware independently booted the 800K disk and
ran both renderer probes. The audited evidence is in
[`runtime/mame-k0.json`](runtime/mame-k0.json), with raw memory captures and
screenshots under `runtime/mame/`. Full module bytes establish the C/D/I/K
placements across intro, game entry and restore; N/R match their original
files at their respective entries. Both probes produce identical 8KiB pages.

The English baseline registers KO18, investigates in Cairo, moves to Istanbul,
and saves the case. A separate MAME process boots a copy of that saved disk
and restores it: all 33 case bytes match except byte `$1A`, which the original
restore routine resets from 3 to 2. The F resume flag is set by save and cleared
by restore. Only F/H change on the saved media. See
[`runtime/mame-save-restore.json`](runtime/mame-save-restore.json).

Probe register restoration must happen at a debugger instruction boundary.
An ordinary MAME pause can occur between 6502 bus cycles even when PC equals
the self-JMP address. The harness now re-arms that address as a breakpoint,
runs to it, and requires a debugger stop before changing PC/P/SP. The final
audit uses the corrected third process, not the earlier failed continuation.

This proxy-glyph experiment is not the final encoding. It does not establish
more than 256 glyphs, final font residency, complete translation capacity,
multibyte scanners or Korean-edition save compatibility. Later full-font,
integration and approved-runtime tests below close those gates. The plan still requires an explicit user decision if a future change
exceeds measured RAM or disk capacity.

## Full-font residency and native library

`runtime/font-residency.json` records a later full-size residency experiment.
The 710-cell, 5,680-byte font occupies auxiliary LC bank 1 `$D000–$E000`
(the first 512 cells) and auxiliary normal RAM `$A700–$AD30` (1,584 bytes).
The bank-2 auxiliary LC interval `$D100–$D140` was tested with a 64-byte helper
canary, and main `$9200–$9800` with a 1,536-byte code/cache canary. All bytes
survived intro/game transitions, a fresh restore, investigation, travel, F/H
saving, return to sign-in and another new-process restore. Data-access taps
were independently retested at every checkpoint. MAME debugger reads with
`machine:side_effects_disabled()` are counted separately. These taps monitor
data accesses; cached instruction fetches are not claimed as read-tap evidence.
The original module/code extents and successful unmodified lifecycle provide
the additional code-ownership context.

That normal-lifecycle canary does not make all of `$9200–$9800` available for
persistent code/data. B's existing TEXT MODE disk-error prompt stages firmware
zero page at main `$9700–$9800` (`B_COPY_LANGUAGE_CARD_PAGE` and
`B_RESTORE_ZERO_PAGE`). The resident library is therefore bounded by `$9700`,
leaving 379 bytes after the integrated 901-byte library/caption engine. The glyph cache at `$97E0` is
disposable and is rebuilt completely on every fetch. No immutable caption,
table or instruction may be placed in the disk-error scratch page.

The base native decoder/installer is 444 bytes at `$9200`; its glyph cache is a
ten-byte header-plus-pixels record at `$97E0`. Its copied LC helper is bounded
by the tested 64-byte reservation. The boot installer stages KF at main `$6000`
and copies exactly 4,096 bytes to LC bank 1 and 1,584 to auxiliary normal RAM.
It runs before R is loaded. The runtime fetch restores bank 2 and main reads
before returning. No additional zero-page allocation is required: the native
glyph scratch pointer `$C8/$C9` is reused, while decoder state is resident
main-RAM data. Native tests preserve A/X/Y, carry, decimal and IRQ state.

The decoder tables occupy the former English dictionary area at LC `$D900`
(256 trail values), `$DA00` (111 lead lows) and `$DA70` (111 lead highs). Their
synthetic C integration preserves the separate original English input
blacklist at `$D7BD`. The earlier component RAM probes borrow and restore those dictionary bytes;
they do not attempt normal English S2 expansion while the tables are installed.

`runtime/native-font.json` verifies all 5,680 installed/fetched bytes through
both text pointers, including IDs above 255 and the bank split at 512. The
sources start at `$A001` so byte pairs cross pages. The native installer first
replaces poisoned font RAM, preventing stale identical bytes from masking a
missed copy. Original C, adjacent auxiliary tail, caller and media are restored.

N's address-preserving text hooks append 212 bytes after its original EOF,
ending at `$8FB4`; R appends 130 bytes, ending at `$7468` before S's `$7800`
load. Their original instruction addresses and direct glyph-index entry points
remain stable. `runtime/native-renderers.json` records byte-for-byte HGR
comparison against an independent pixel reference, centered mixed text,
page-crossing pairs and bounded hard wrapping. The narrow typewriter also
matches its complete expected drawing-call glyph stream. Its original leading
`$80` indentation marker is retained.

## Disk-booted synthetic text integration

`make korean-synthetic` builds a separate 800K disk with a bijective permutation
of the draft's Hangul cells. No approved translation is implied. Its actual
file/RAM sizes are recorded in `synthetic-build.json` and detailed generated
text/operand patches in `synthetic-text-assets.json`.

| Synthetic allocation | Bytes / boundary |
| --- | --- |
| WORLD.SYSTEM | 1,365 bytes; boot-only main `$2000–$2555` |
| B | 1,152 bytes; main `$9800–$9C80`; eight public entry addresses preserved |
| C | 10,105 bytes; same staging/copy regions and fixed tables/icons; original English blacklist at `$D7BD`, repacked display names/traits and UI |
| D | 1,507 bytes; main `$B900–$BEE3`, 29 bytes before ProDOS; unchanged 107-glyph count, clock words replace only glyphs `$85/$86` |
| N | 12,492 bytes; main `$6000–$90CC`, 308 bytes before KL; renderer/reader helpers, relocated save message and picture-caption hooks |
| R | 5,652 bytes; main `$6000–$7614`, 492 bytes before S at `$7800`; renderer helpers, intro strings and picture-caption hooks |
| I / K | 1,698 / 1,178 bytes in their unchanged 4KiB auxiliary reservations |
| S2 | 101,155 bytes; 30 rebuilt records with identical compressed city pictures and preserved structural NULs |
| KL / KF | 901 / 5,680 bytes; KL ends at `$9585`, before B's `$9700` disk-error scratch page; font placement unchanged |

WORLD loads KL at `$9200` and KF at main `$6000` after the original auxiliary
copies/C installation, calls the native installer, then loads R. The updated
B module tables add those two paths without moving the public services.
Runtime checks compare both complete font banks, C, I/K, D, the LC copy helper
and immutable decoder/caption instructions after actual boot and at each lifecycle
checkpoint. N is compared in full before its first instruction executes.
The decoder's documented mutable operands/state and glyph cache are excluded
from the immutable-instruction claim.

`runtime/synthetic-text.json` covers intro/title, registration, investigation,
computer and trait selection, planned travel, F/H save, return to sign-in and
fresh-process restore at 23 resident checkpoints. The native
reader stress fixture reaches 1,698 output bytes without touching its remaining
buffer canary. `runtime/native-clock.json` covers all clock field values and
sequential redraws: weekday and full meridiem share the upper row, with original
Arabic hour digits below, inside the original clock panel. No new compression,
asset streaming, extra RAM or extra media has been introduced.

The caption engine appends 457 bytes at `$93BC–$9585`. It backs up all 256
zero-page bytes and changes only the lettering rectangles after the original
RLE decoder returns. `runtime/native-captions.json` compares all 11 captions
on both pages against independent font pixels, all bytes outside the affected
picture columns, and the original decoder's registers/flags/zero page. The
original compressed S/O/P files remain unchanged.

`draft-capacity.json` and `message-layouts.json` cover all native city selectors,
1,697 report combinations, 1,023 nonempty warrant subsets and fixed fields.
`runtime/native-messages.json` verifies all 47 synthetic extrema, including
the extra scroll at a terminal NUL after trailing breaks. All 60 actual native
city record/text loads, including 24-bit offsets above 64KiB, pass in
`runtime/native-cities.json`. Stored text stays below `$A700`, and even the
2,604-byte largest compressed picture plus the native extra NUL stays below
the `$1D00` index buffer.

The repeated disk image has 1,179 free ProDOS blocks. `review-readiness.json`
joins these exact-image reports and accounts for all 1,287 draft targets,
including retained unselected fields and the floppy-only variant. The approved
image uses the same allocations with literal Korean text. Its native lifecycle,
paired gameplay and save tests pass in `runtime/approved/`. Actual TEXT/HGR disk
error recovery also confirms that the font and resident code survive B's scratch
page use. Detailed captures are in the [runtime evidence archive](runtime/README.md).
