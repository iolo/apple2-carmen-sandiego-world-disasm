# Where in the World is Carmen Sandiego? (Apple II) reconstruction

This repository reconstructs three supplied ProDOS disk images: the two 140 KB
floppies and a related 800 KB release. The game files are extracted into
`assets/`; candidate executable files are represented as ca65 source in
`src/`. The rebuild creates fresh disk images, so block allocation and unused
space can differ from the supplied disks.

See the [source guide](docs/source-guide.md) for module entry points, the case
state layout, graphics indexes, and assembly conventions.
The [verification audit](docs/verification.md) maps the PRD deliverables to
the source, extracted assets, build checks, and observed runtime evidence.

## Build and verify

Install Python 3, `a2kit`, `ca65`, `ld65`, and optionally MAME with Apple IIe
ROMs. Then run:

```sh
make extract   # recover source files and decoded asset views
make build     # assemble game code and create three disks in build/
make check     # rebuild, then check file bytes, EOF, type, and load address
make test      # focused case-state, directory-coverage, and speaker checks
make smoke     # run the rebuilt floppy pair for 20 emulated seconds in MAME
make inventory # show files, sizes, addresses, and build inputs
```

`make check` also verifies the original disk hashes and complete root-directory
file coverage, including volume names and declared file counts.

`make build` uses the checked-in extracted assets and source; `make extract` is
only needed to regenerate them from the original images. Set `MAME_ROMPATH`
if your ROM collection is elsewhere. Interactive boot and gameplay have also
been checked with Apple2TS; see [reconstruction notes](docs/reconstruction.md).
The decoded assets include the 128-word text dictionary in `C` and all 920
text lines from each release's `S2` world records. Each decoded line has
female and male previews for the game's `#`, `@`, and `^` pronoun markers.
The build reads editable
tokenized text and compressed city-image commands from `assets/s2_source/`.
The HGR splash page `A` rebuilds from editable pixel rows and color-phase bits
in `A-hgr.json`; its PNG is a monochrome preview.
`C-ui-text.json` also contains 130 editable interface strings, and
`C-icons.json` contains 30 embedded bitmap records with PNG previews. Both
rebuild into the `C` module.
`C-animation-pointers.json` maps another `C` pointer table to T's five frames
and U's 26 sprites in the stored order, including their direct glyph indexes
`$89`–`$A7` used by the game renderer.
The 30 landmark images in each release also have PNG previews.
The `F` roster, `G` hall-of-fame name slots, and `H` saved-case pages rebuild
from structured JSON views.
`H-cases.json` adds readable case fields joined to suspect, city, weekday,
and clue names, while retaining all route slots and the separate roster
resume flag. It is a decoded view; `H.json` remains the editable build input.
Each occupied `H.json` slot now stores a named `case_state` instead of a hex
string. All thirteen route slots and six trait values are preserved, including
stale or unset bytes; `tools/case_state.py` encodes the exact 33-byte layout.
The `D` bitmap font rebuilds from editable glyph rows in `D-font.json`, with
an ASCII preview in `D-ascii.png`.
`I` and `K` rebuild from editable NUL-delimited text lists in
`assets/text_source/`.
`J` rebuilds from eight editable city-connection maps in `J-routes.json`.
The twelve embedded speaker tracks are readable in `N-sounds.json` and
assembled from the shared `src/shared/n_sounds.inc` source.
The 800 KB release's save-dialog message rebuilds from editable text and
control-byte segments in `N-save-dialog.json`.
`N-suspect-traits.json` joins each suspect's six trait values in `N` with the
names and clue labels extracted from `C`.
`N-city-map.json` joins the thirty city marker positions and route coordinates
to the city names, including the route plotter's two-pixel X units.
The thirty city-specific, twelve-choice clue-count rows at the end of `N`
assemble from editable `src/shared/n_city_clue_counts.inc`. Extraction also
writes `N-city-clue-counts.json`, grouping each city's S2 clue text by choice.
The intro overlay's two tracks are in `R-sounds.json` and
`src/shared/r_sounds.inc`.
All fourteen tracks also have playable `N-sound-*.wav` and `R-sound-*.wav`
previews for each release. `N-audio.json` and `R-audio.json` record their
durations and speaker-toggle counts. The renderer runs the stored player
instructions using a declared 1 MHz clock and a simple speaker filter.
Its eight embedded bitmap glyphs rebuild from editable rows in
`R-glyphs.json`, with individual PNG previews under `assets/decoded/`.
`S` is split into four compressed HGR image records, with decoded PNG previews
in `assets/decoded/`.
`S` and `O` rebuild from editable literal and repeat commands in
`assets/s_source/` and `assets/o_source/`; their original records remain under
`assets/s/` and `assets/o/`.
`P` has two decoded image previews from overlapping parts of one editable
stream in `assets/p_source/`.
`T` and `U` rebuild from editable bitmap rows for five animation frames and
26 character and object sprites, each with a PNG preview.

The ca65 sources have named routines and annotated control flow, including
the loaders, game menus, case state, text and graphics rendering, sound players,
intro, and disk controller. Identified strings, tables, ProDOS parameter blocks,
and patched instruction operands are represented explicitly. Every module
assembles back to its original bytes. `E` is regenerated from its decoded
shift-table formula. Some retained routines have no identified caller, and
several small data regions and controller firmware behaviors remain unresolved;
see the [analysis limits](docs/reconstruction.md#current-reverse-engineering-limits).
