# Reading the reconstructed source

Start with the floppy release in `src/disk1/`. The related 800 KB release is
in `src/po/`; its C, Q, and R files include the byte-identical floppy sources.
The other modules retain separate sources because their bytes differ.
The original load address and SHA-256 appear at the top of each source.

## Modules

| Module | Address | Purpose and useful entry points |
| --- | --- | --- |
| [WORLD.SYSTEM](../src/disk1/WORLD.SYSTEM.s) | $2000 | `BOOT_ENTRY`: memory setup, file loading, installation of resident services, intro handoff |
| [B](../src/disk1/B.s) | $9800 | Eight-entry public table: module loads, intro/game handoffs, S2 reads, F/G/H writes |
| [C](../src/disk1/C.s) | $D200 | Ten-entry public table: string selection/copy, graphics-span transfers, auxiliary-memory copies; followed by lookup tables and assets |
| [R](../src/disk1/R.s) | $6000 | `R_INTRO_ENTRY`: logo, animation, globe, title; `R_ENTER_GAME` returns to B's game loader |
| [N](../src/disk1/N.s) | $6000 | `N_MAIN_ENTRY`: registration, cases, city commands, investigation, warrants, rendering, input, sound, and saves |
| [Q](../src/disk1/Q.s) | $1F00 | Memory scrub, mapping restore, reset-vector handoff |
| [Z](../src/po/Z.s) | $4000 | 800 KB release only: SmartPort probe, signature check, AppleDisk callback, downloaded UniDisk controller program |

R and N occupy the same address range at different times. Their code is not
simultaneously resident. A file's ProDOS auxiliary load address is not a
complete runtime memory map: the loader stages and copies several modules.
For example, it installs C's first two service pages at $D200–$D3FF and
copies lookup/data pages to auxiliary memory.

## Follow one case through N

1. `N_MAIN_ENTRY` selects a route graph, initializes the clock and filters,
   and either signs in a detective or begins another case.
2. `N_REGISTER_DETECTIVE` reads a name, searches F, and handles registration
   or the saved-case prompt.
3. `N_BEGIN_CASE` chooses the suspect and final hideout.
   `N_GENERATE_ROUTE_STEP` constructs the route backward from that hideout.
4. `N_PREPARE_CITY_MENU` and `N_PREPARE_CITY_CLUES` set up a city.
   `N_DRAW_CITY_SCREEN` displays the name, landmark, description, and commands.
5. `N_TRAVEL_TO_SELECTED_CITY` draws the map route and advances the clock.
   Investigation selects place animations and clue text.
6. `N_FIND_WARRANT_MATCHES` compares the six selected traits against the
   suspect matrix. The result/report paths handle arrest, failure, promotion,
   and the hall of fame.
7. `N_SAVE_CURRENT_CASE` writes H and sets the roster flag in F.
   `N_RESTORE_SAVED_CASE` restores the case, resets the menu selection to 2,
   clears the flag, and reloads the selected route graph.

## Persistent case bytes

`tools/case_state.py` is the lossless codec for the 33-byte snapshot at
CPU-visible zero page $00–$20. On the observed game screens, ALTZP selects
auxiliary zero page; read the current mapping before comparing memory.

| Bytes | Meaning |
| --- | --- |
| $00–$02 | Suspect, route-graph selector, route index |
| $03–$0F | Thirteen route slots; unused slots can retain stale values |
| $10–$11 | Final hideout and current city |
| $12–$15 | Current weekday/hour and deadline weekday/hour |
| $16–$1A | Investigation count, warrant suspect, sound flag, treasure-text index, city-menu selection |
| $1B–$20 | Sex, hobby, hair, feature, vehicle, food filters; $FF means unset |

F has thirteen 19-byte detective records. Each record holds a 16-byte name,
rank, solved-case count, and resume flag. H has thirteen corresponding
256-byte pages. An occupied page contains the 33 snapshot bytes and 223 zero
bytes; an unused page is all $FF. A populated H page does not by itself mean
that F's resume flag is set. G holds sixteen hall-of-fame names.

## Graphics, text, and sound

- C's string services select NUL-delimited entries and append into a buffer.
  S2 text uses C's 128-word dictionary and the game's pronoun substitutions.
- N and R have distinct HGR image decoders. Their labeled header, literal,
  repeat, stride, and row-address paths correspond to the editable streams
  in `assets/`. A repeat count of zero means 256 copies.
- `N_PREPARE_GLYPH_CHAR` subtracts $20 from a character code;
  `N_PREPARE_GLYPH_INDEX` accepts an index directly. Indexes $00–$6A use D,
  $6B–$88 use C icons, and $89–$A7 use the adjacent T/U animation pointers.
  These two inputs must not be confused.
- `src/shared/n_sounds.inc` and `r_sounds.inc` contain the speaker sequences.
  Their player routines interpret note indexes, duration commands, rests,
  and $FF endings. WAV previews execute those player bytes at a declared
  1 MHz clock; they are not hardware recordings.

## Source conventions and limits

Named labels describe the observed control flow. `:=` aliases often identify
an instruction operand modified at runtime; they do not allocate extra bytes.
An isolated `.byte $2C` can be an intentional BIT instruction that skips the
following two-byte immediate instruction. ProDOS MLI calls use inline function
bytes and parameter pointers, which must not be decoded as subsequent code.

The build generates C text/icons, R glyphs, and the 800 KB N dialog includes
from editable JSON. These temporary includes are data declarations, not copies
of the original executable. No game assembly source uses `.incbin` to hide
its executable bytes. ProDOS and Finder metadata remain external files.

Unidentified trailing data and dormant entries are preserved and described
without assigning unsupported meanings. The Z firmware services and physical
controller paths have not been fully established. Consult the
[reconstruction notes](reconstruction.md#current-reverse-engineering-limits)
for specific uncertainties and the recorded runtime checks.
