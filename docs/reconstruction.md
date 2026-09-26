# Reconstruction notes

## Disk and module map

The first 140 KB ProDOS disk contains `PRODOS`, `WORLD.SYSTEM`, and game files
`A` through `U` (with gaps in the lettering). The second disk contains the
large `DATA.S2` world-data file and `FINDER.DATA`. The 800 KB ProDOS image
combines a related, changed revision: its `WORLD.SYSTEM`, `B`, `N`, `F`, `H`,
and `S2` differ, and it adds executable `Z`. `C`, `Q`, `R`, and many data files
match the floppy release. The 800 KB image's `S2` is related to, but differs
from, floppy disk 2's `DATA.S2`.

The ProDOS binary is retained as an external system dependency. `WORLD.SYSTEM`,
`B`, `C`, `N`, `Q`, `R`, and the 800 KB image's `Z` have ca65 listings. Their
load addresses and ProDOS metadata are in `reconstruction/manifest.json`.
`WORLD.SYSTEM` starts at $2000, sets up memory, and loads overlays; `B` starts
at $9800 and supplies a file loader called by the boot module. `N` and `R`
both load at $6000 at different times. These are overlays, not simultaneous
residents. The `B` dispatch table has 17 one-character Pascal filenames, in
module-index order `E D F G O J C K I P T U N H Q R S`, with a buffer page
for each. The primary code also uses language-card and auxiliary memory.
`Q` is byte-identical in both releases and has been reviewed as a memory-scrub
and reset routine. Its apparent `BRK` and `JSR` bytes in the mechanical
listing were the operands of self-modifying `STA absolute,Y` instructions.
Its loops and patched high-byte operands now name the main, auxiliary, and
language-card passes; the final page-three clear jumps through the reset
vector. The shared `Q` source has no address-only labels.
The boot and `B` listings now use the Apple II monitor names `VTAB`, `HOME`,
`PRBYTE`, and `COUT` for their ROM calls at $FC22, $FC58, $FDDA, and $FDED.
These entry names are confirmed by the [Apple II Reference Manual](https://www.applelogic.org/files/AIIREF.pdf).
`G` is a 256-byte hall-of-fame list with sixteen FF-padded name slots. Both
supplied revisions have empty slots; `assets/decoded/*/G.json` makes the names
editable while preserving those original bytes. Registration compares new
names against this list after rejecting matches in fifteen C strings starting
at $DC0F (ten suspect names followed by five detective ranks). After Carmen
is caught, `N` copies the detective's name to the first empty G slot (or the
last slot when full), saves G, clears that detective's 19-byte F record, and
saves F.
The 800 KB release's `Z` module mixes 6502 and 65816 code. Its routine at
$41A7 contains `PHB`, `PLB`, and `RTL`, so the original 6502-only listing was
misleading. `Z` probes a SmartPort slot ROM by matching bytes at four offsets,
patches a JMP to its entry point, and passes three-byte inline
command/pointer pairs to that entry. It also accesses Disk II soft switches at
$C0E0-$C0EF. Its SmartPort parameter blocks and UniDisk download are now
identified; several other `Z` regions still need analysis.

`A` is an 8 KiB HGR splash page (the ProDOS EOF omits the final byte). The
decoder produces a 280×192 monochrome preview. Its editable `A-hgr.json`
stores 192 pixel rows, forty color-phase bits per row, and the 511 retained
bytes outside the visible scanlines. The builder regenerates the original
8191-byte file from those fields. `D` contains 107 variable-size
bitmap glyphs for character codes $20–$8A. Its first 224 bytes are parallel
low- and high-byte pointer tables with five unused zero entries. Each glyph
has two dimension bytes followed by packed bitmap rows, with seven visible
pixels per bitmap byte. `assets/decoded/*/D-font.json` preserves every bit,
including one set eighth bit, and the builder regenerates the pointer tables
and records from it. `D-ascii.png` previews the printable glyphs. `F` contains fixed-size
detective records. The 13-slot roster uses 19 bytes per slot: a 16-byte name
and three status bytes. `N` loads them as rank index, solved-case count, and
saved-case flag. Its promotion thresholds start 1, 5, 12, and 20 solved
cases; the remaining two entries are $FF. The final slot and nine trailing
bytes are $FF in the supplied files. `C` generates the 13 record offsets at
$D7B0, and `N` uses
them for detective lookup and registration. The builder now reconstructs `F`
from the editable `assets/decoded/*/F.json` rosters, preserving status
bytes and the nine-byte tail. `H` has thirteen 256-byte pages in the same slot
order. `N` loads `H` at $1100 and addresses a detective's page as
`$1100 + slot * $100` when saving or restoring a case. A used page stores
zero-page bytes $00–$20 in its first 33 bytes and has 223 zero bytes after
them; an unused page is all $FF. The build regenerates `H` from editable
`assets/decoded/*/H.json`; `assets/h/` retains exact page extracts.
Some pages contain data even when the corresponding `F` saved-case flag is
clear, so the page content alone does not prove an active saved case. The
unused route slots can retain values from earlier cases; their extent is not
inferred from the presence of a stored city value.
`H-cases.json` now joins the confirmed suspect, route, origin, final hideout,
current city, clock, deadline, warrant, sound flag, and trait-filter bytes to
their C names. All thirteen route slots remain visible because bytes beyond
the hideout can contain stale values. The roster's saved-case flag is reported
separately from the presence of an H snapshot; an empty F slot has no resume
flag. The view also names the route-graph selector at $01, completed-city
investigation count at $16, treasure-text index at $19, and saved city-menu
selection at $1A. The treasure index selects one of I's three strings per
origin city. The route selector chooses which of J's eight 256-byte pages C
copies to auxiliary $9F00. The investigation count resets on entering a city
and controls visit time and the first-visit hideout behavior.
The build input `H.json` now stores these fields in a named `case_state` for
each occupied slot. `tools/case_state.py` decodes and encodes the complete
33-byte layout, preserving all thirteen route slots and six trait bytes.
It rejects missing fields, incorrect array lengths, and values outside the
byte range. Unused pages remain explicit FF markers; original snapshots also
remain in the binary H extracts and `H-index.json` hex views.

`N`'s save path now shows the full H/F update: it clears the selected H page,
copies case bytes $00–$20 into it, saves H, sets that detective's saved-case
flag in F, and saves F. Resuming copies those bytes back into zero page and
clears the flag; declining the resume prompt clears the flag without copying
the page. The day/hour fields are named in both `N` listings. Each hour
advance checks the stored deadline, rolls the day after hour 23, and at hour
22 advances through the night to hour 7 before returning to the menu.
At case start, `N` clears all six suspect trait filters to $FF, chooses a
weekday from 0–6 and a starting hour from 08:00–17:00, then sets the deadline
to the same hour six days later (weekday minus one modulo seven).

`G` has sixteen editable hall-of-fame name slots, all empty in the supplied
releases. `I` and `K` contain only NUL-terminated ASCII text. The builder
reads editable strings
from `assets/text_source/`, including `I`'s final empty entry; decoded views
retain the original byte offsets.
`J` is eight 256-byte city-connection graphs. Each page stores the 30 cities'
destination lists at the front and 31 byte offsets at $D8–$F6; the intervening
and trailing bytes are zero. Every list has three to five destinations, and
every edge is reciprocal. The build reads editable city names and connections
from `J-routes.json` and regenerates all eight pages.
The boot loader reads `O` into main RAM at $A700. It stages `P`, `T`, and `U`
at $6000 and copies them into auxiliary RAM at $8000, $8500, and $9400,
respectively. `N` has six parallel metadata tables for drawing compressed HGR
images. Four pointers lead into `O`: the top screen panel, lower panel, world
map, and suspect search terminal. Their markers, extents, and zero padding
match the decoder, and the build joins their four exact records from
editable literal and repeat streams in `assets/o_source/`; `assets/o/` retains
the original compressed records for comparison. The build checks each O
source's geometry against `N`'s metadata and preserves the fixed loaded
addresses with zero padding. Two other metadata entries point into `P` after it is copied to
$1100. They render a sparse overlay and a jail picture from overlapping
parts of the same byte stream. `assets/p_source/*/P.json` preserves the shared
five-byte prefix and exposes picture 5's literal and repeat commands. The
builder verifies both pictures decode from the resulting 1060-byte stream;
the original `P.bin` remains available for comparison.
`assets/decoded/*/O-*.png` and `P-*.png` preview these pictures. The formats
of `T` and `U` are variable-size bitmap records. Both `N` revisions now use
the named picture metadata and HGR masks in `src/shared/n_picture_tables.inc`,
and the drawing entry at $7FAC is labeled `HGR_RLE_DRAW_N`.
Both `N` revisions now name the picture decoder's metadata lookup, literal
and repeat paths, scanline/column advance, and optional second pass. Its
HGR address helper combines scanline Y with byte column $70 and returns Y=0
for direct indexed writes. A zero repeat count produces 256 copies.
`T` has five 75×68 frames of a city scene. `U` has 26 character and object
sprites of varying sizes. Each record starts with width and height bytes,
followed by `height * ceil(width / 7)` bitmap bytes. Seven bits per byte are
visible pixels; the eighth bit is retained in the editable JSON rows for an
exact rebuild. `assets/decoded/*/T-sprites.json` and `U-sprites.json` drive
the build, and each record has a PNG preview beside its JSON source.
`S` contains four compressed HGR images at loaded addresses $7800, $7BE0,
$7FA0, and $8760. `R` calls its decoder at $69BE with each of these addresses.
A six-byte header gives the first and last byte columns, first and last
scanlines, repeat marker, and scanline stride. A marker in the body is followed
by a byte value and repeat count; zero count means 256 copies. Stride two
stores alternating scanlines in separate passes. The four decoded previews
show the Broderbund logo, globe, title screen, and ACME storefront. The build
assembles editable literal and repeat streams in `assets/s_source/` into the
four fixed-size records; `assets/s/` retains the original compressed bytes.
The previews and headers are in `assets/decoded/*/S-*.png` and `S-images.json`.
The large S2 data files start with a 192-byte
table of 24-bit record offsets, yielding 30 data records. Each record is a
separate exact binary extract under `assets/s2/`. The build inputs under
`assets/s2_source/` split each record into JSON text lines and a JSON stream
of city-image literals and repeat commands. Exact binary suffix extracts
remain beside those sources for comparison. Braced words such as `{is}` represent single-byte dictionary
tokens; literal text stays unbraced. Empty lines preserve NUL separators.
The builder regenerates each record's text/binary pointer and the outer offset
table from their lengths. The decoded index lists record bounds and readable
ASCII runs. Each S2 record begins with a 16-bit little-endian offset to its
binary section. Bytes from offset 2 to that boundary are NUL-separated text;
bytes $80–$FF expand through a 128-word dictionary embedded in `C`. The
`C-dictionary.json` and `S2-text.json` views expose all 920 decoded lines in
each release, with original file offsets. The S2 view retains `#`, `@`, and
`^` in `text` and also supplies female and male previews using the game's
subject, possessive, and object substitutions. Its dictionary spacing follows
the assembly routine's punctuation rule. The `C` assembly now declares the
dictionary as 128 NUL-terminated strings; the 800 KB release includes the
byte-identical floppy source. The following `C` tables contain 30 city names,
10 suspect names, six detective ranks, and seven weekday abbreviations;
these are declared as strings in the assembly and indexed in `C-names.json`.
Seven parallel suffix strings complete the weekday names when `N` appends
"day". For example, `Wed` plus `nes` forms Wednesday and `Sat` plus `ur`
forms Saturday. Both `N` revisions now name the prefix and suffix table
addresses, and `C-names.json` lists each complete result.
The 23 suspect clue labels are likewise declared as strings and grouped in
`C-clues.json` by sex, hobby, hair, feature, vehicle, and food.
Another `C` region at $E000–$EB3A holds 130 NUL-terminated interface strings.
The extractor separates printable text from the observed $80–$82 and $8D
control bytes in `C-ui-text.json`; 197 zero bytes pad the region to $EC00.
The source builder generates this text region from the editable JSON. The
following $EC00–$F978 region contains 30 packed bitmap records in the same
width/height and seven-pixel row format as `T`, `U`, and `R` glyphs. Their
split low/high pointer tables start at $DD00 and $DD3E. `C-icons.json` drives
the builder, and individual PNGs preview each icon. Four bytes at $F917–$F91A
follow icon 27 outside its declared height; their role is unknown and their
exact values are retained in that icon's `trailing_hex` field. Its width 27
requires four packed bytes per row, and its height 14 covers 56 body bytes.
The four retained bytes could occupy another row, but the glyph preparation
and row-copy loops use the declared height and do not consume them as part
of this bitmap. The generated assembly now separates each icon's dimensions,
packed rows, and any retained tail; it labels this tail explicitly. The two
adjacent 32-byte tables are another split pointer set: five `T` frame pointers,
all 26 `U` sprite pointers in a reordered sequence, and a zero terminator.
They address bitmap records at a common $0E00 base. The extractor verifies
each target against `T-sprites.json` or `U-sprites.json` and writes
`C-animation-pointers.json`; the builder regenerates both table halves from
that mapping. These tables continue the preceding icon pointer tables:
N's direct glyph indexes $00–$6A select D, $6B–$88 select C's 30 icons,
and $89–$A7 select the five T frames and 26 U sprites. Index $A8 reaches
the zero terminator. Character input first subtracts $20, while direct glyph
input uses the stored index unchanged. Each animation mapping now records its
`glyph_index`. The arrest-scene immediate $A6 therefore selects animation
entry 29, U sprite 24 at $18EF, rather than C icon 27 (character $A6).
Both `N` sources name this arrest marker index explicitly.
Both `N` revisions now name their reads from C's icon pointer
table. The `N` glyph preparation routine uses `D` for character codes
$20–$8A and these 30 `C` bitmaps for $8B–$A8; `C-icons.json` records each
bitmap's character code.
The glyph renderer now names its entries for positioned glyph indexes,
current-position indexes, and ASCII characters. Its cursor helper advances
or backs up by the prepared glyph width, carrying between seven-bit HGR byte
columns. Preparation reads width and height from the selected bitmap and
counts its packed bytes per row.
The adjoining text renderer measures glyphs before drawing each run. At byte
column 39 it backs up to a space and continues on the next scanline; $8D and
$8F select the normal and alternate left margins. Its centered-string entry
measures the complete UI string, subtracts half its width from the requested
horizontal position, and can record the resulting menu left edge.
The bitmap writer below it has direct-copy and shifted masked-copy/XOR
entries. The shifted writers use the E lookup pages and start/end masks to
preserve pixels outside the horizontal clip rectangle. The masked-copy entry
replaces complete interior bytes and merges only the edge bits; the XOR entry
is used for glyph drawing.
The fill and clear rectangle routines similarly mask their first and last
HGR byte columns, write whole interior bytes, and advance scanline by scanline.
At a boundary bit offset of six they also update bit zero of the adjacent
byte. Both revisions now name these row and edge paths.
The callers below these routines clear fixed picture and menu regions or
draw one of six framed menu rectangles. The travel frame computes its lower
edge from the current city's route count. Its patched immediate operands now
name the inner and outer edges; a separate nested A/Y countdown supplies
the short delays used by animation and keyboard feedback.
The shared menu input loop accepts both Apple II arrow-key code pairs:
$08/$0B move to the previous option, and $15/$0A move to the next. It wraps
at the menu endpoints, redraws the active highlight, recognizes Return and
Escape, and sends other command keys through the global dispatcher.
The same loop treats joystick button 0 as Return and button 1 as Escape.
It strobes paddle timers at $C070, samples $C064/$C065, and classifies values
below $18 or at least $A8 into four direction bits. Those bits feed the same
previous/next selection paths as the arrow keys. The old highlight and any
travel destination marker are cleared before the new selection is drawn.
The following input helpers accept Y/N with echo, backspace editing, and
Return; compare detective names without ASCII case; and dispatch the eight
global control keys. The HGR presenter displays the page selected by $74 and
copies it into the other 8 KiB page so animation can continue from the same
picture. A retained 13-byte stub can be copied to $0100 for a bank/display
restore and ROM jump, although no direct local call to its installer is known.
The standard screen background draws common glyphs and bars; city mode adds
the landmark decoration and clock. Weekday, hour digits, and AM/PM are separate
entries for clock refreshes. A decimal helper draws case counts by subtracting
hundreds and tens, omitting leading zeroes. The bounded random helper's state
update and repeated subtraction are also labeled in both revisions.
The report text renderer measures and wraps each run, then reveals characters
one by one while polling for global control keys. At line boundaries it copies
the report region between HGR pages to scroll the visible text, refreshes the
lower border, and handles the normal or alternate next-line margin. The
follow-up prompt and generic disk prompt now have named drawing paths.
Both `N` revisions now have no remaining address-only `Lxxxx` labels. The
last retained aliases were unused mechanical markers; the active connection
toggle and patched random animation call now have purpose-based labels.
This label cleanup does not, by itself, prove that every code/data boundary or
zero-page field has been interpreted.
The 470 zero bytes between C's final clue label and its $E000 interface text
are declared as padding. The earlier mechanical aliases created by treating
the text and bitmaps as instructions are no longer needed in the `C` listing.
Literal `@` and `#` placeholders are retained. Each binary suffix is one
compressed landmark image, loaded at $1100 for `N`'s picture-0 decoder.
Its first byte is the scanline stride and its second byte is the repeat marker;
the following bytes contain literals or marker/value/count runs. The builder
recreates these streams from `assets/s2_source/*/*-image.json`, and the 30 PNG
previews and city names are indexed in `S2-images.json`. Twenty-nine images
fill their declared rectangles exactly. City record 8 ends three pixels early
in both releases; its preview leaves those pixels black and preserves the
original short stream. `E` is seven
256-byte pages of 7-bit shift lookups: for shift
0–6, the first 128 bytes are `(input << shift) & $7F`, and the second 128
are `input >> (7 - shift)` for input 0–127. Both releases match this formula
exactly, and the builder regenerates `E` from it. Original binary extracts
remain available for every asset.

## Build checks and observed runtime

The full `make extract` → `make check` workflow has also passed in an isolated
temporary copy containing only the three original disk images, current tools,
Makefile, and assembly sources. The extraction generated all build inputs,
including the named saved-case states and WAV previews; the subsequent build
and check verified all 48 file instances. Existing decoded assets were not
copied into that test workspace.

`make check` compares the rebuilt 48 file instances with their source image
files, including SHA-256 of bytes through ProDOS EOF, EOF itself, file type,
and auxiliary type/load address. The source listings were also assembled and
compared byte for byte to their extracted binaries. The disk builder creates
fresh ProDOS filesystems, then inserts the rebuilt file images. It does not
recreate timestamps, physical allocation, unused blocks, or disk 1's malformed
directory entry (which makes `a2kit tree` fail on the original image).
The directory audit reads the logical root-directory block chain, checks its
backlinks and declared file count, and compares every valid filename with the
build inventory. Disk 1 declares and contains 21 valid files; the invalid
storage byte $AC at block 5, slot 12 is recorded with its full entry bytes in
the manifest as unused directory data. Disk 2 and the 800 KB release contain
two and 25 valid files respectively with no such entries. Extraction now
records this inventory, and checking verifies the source-image hashes,
volume names, complete file coverage, and absence of malformed entries in the
rebuilt directories. `test_inventory.py` verifies that omitting a valid file
or changing the declared count causes verification to fail.

On 2026-09-26, `make smoke` ran the rebuilt floppy pair in MAME Apple IIe for
20 emulated seconds. In Apple2TS, the rebuilt floppy pair reached the
Broderbund splash, detective registration, and the first case announcement;
registration accepted a new detective name. The rebuilt 800 KB image booted
as `hd1` in Apple2TS and reached the detective registration screen. The latter
runtime test does not prove every case-data read, disk swap path, sound, or
save operation.

A later private Apple2TS `APPLE2EE` run of the rebuilt floppy pair advanced
through registration and a New Delhi case announcement to the New Delhi city
screen. It displayed the landmark picture and description; choosing
Investigate, then Marketplace, produced the clue about buying a ship to sail
around the world. This exercises one S2 city record and investigative text in
addition to the opening assets. The session was stopped after that clue;
at that point, travel, disk swaps, sound, and saved-case restoration were
unverified.

In a separate private Apple2TS `APPLE2EE` run of the rebuilt floppy pair, a
new detective named CODEX received a San Marino case about the Regent's stamp
collection. From the San Marino city screen, `Depart by Plane` listed Lima,
Buenos Aires, Rome, Moscow, and Budapest. Selecting Lima reached its city
screen with the Archbishop's Palace landmark picture and description. Choosing
`Investigate`, then `Sport Club`, displayed a clue about the thief seeking a
lost Siamese temple. Both rebuilt floppies were mounted during this run; this
verifies one travel and subsequent clue path. It does not verify a prompted
disk swap, sound output, or saved-case restoration.

The latest private 800 KB `APPLE2EE` check mounted the rebuilt image as `hd1`,
registered rookie detective ADT, and reached a case starting in Paris. The
city screen displayed the Eiffel Tower image and Paris description.
Investigate → Bank produced “He changed his money to dollars. He had a nice
convertible.” The [runtime record](runtime/po-boot.json) retains the uploaded
image hash, case-state bytes with their auxiliary-memory mapping, and
[screen evidence](runtime/po-paris-clue.png). The observed route was Paris →
New York → Beijing → Budapest; `$10` held the final hideout, Budapest, rather
than the starting city. The private session was stopped after the check.
This run establishes boot, registration, and one clue path; it does not
establish case completion, save/resume, audio, or physical controller paths.

A subsequent private 800 KB run tested save/resume with rookie detective QA
in roster slot 3. The new case started in Buenos Aires at Sunday 3 PM.
Visit Interpol → Save Case → Return wrote the exact 33 case bytes to H page
$1400 and cleared the remaining 223 bytes to zero. The roster resume flag
changed from 0 to 1. After booting again with the same mounted media, signing
in as QA offered the resume prompt; accepting it restored the Buenos Aires
case and cleared the flag to 0. Of the 33 bytes, only $1A changed, from 3 to
2, exactly as the resume entry's menu-selection reset specifies. The
[runtime record](runtime/po-save-resume.json) includes the mapped memory reads,
roster snapshots, image hash, and cleanup receipt. The
[saved-case confirmation](runtime/po-save-confirmation.png) provides display
evidence. The resumed city screen was observed live; a later black capture
was excluded from the archived evidence.
The private session was stopped. This verifies one save/resume path across
emulator boot on the 800 KB release; it does not verify exporting and
remounting modified media, floppy disk swaps, or a completed case.

## Current reverse-engineering limits

The ca65 sources are byte-exact annotated disassemblies. Identified ProDOS MLI
parameters, strings, tables, and self-modifying operands are separated from
instructions. Descriptive labels and a successful rebuild do not establish
every external entry point or all hardware behavior; the specific remaining
questions are recorded below.
Both `WORLD.SYSTEM` loaders now distinguish ProDOS call bytes, file request
blocks, load tables, and message strings from instructions; one interrupted
instruction sequence was corrected in each. Further split `JSR` and `LDA`
instructions were restored in their RAM-disk checks, and their patched
delay-loop immediate operands are no longer shown as `BRK`. The 800 KB loader
skips a 51-byte fragment at $20A7–$20D9 after reading `Z`; no local control
flow enters it. The first eight bytes match Z's inline arguments. They are
followed by a carry/error check and an unsigned Y:X range check
($1DB0–$1EA9), then a second Z call with its own arguments and a range check
($206C–$2101). The source now separates those data records from instructions;
why the fragment is skipped remains unknown.
Both loaders' title, memory requirement, RAM warning, continue/quit,
and load-error messages now have named labels; the display paths select them
through symbolic low/high pointers. Their fixed-row-ten centering entry is
also named separately from the entry that accepts a row in A.
The OPEN/READ/CLOSE request
blocks, four disk-prompt strings, and 17-file dispatch table at the end of
both `B` loaders are now marked as data; all their recognized ProDOS MLI call
sites show the function byte and parameter pointer explicitly. The eight
public `B` jump entries now name module loading, intro/game entry, S2 record
and text reads, and F/G/H saves. Both releases' S2 reads name their OPEN,
SET_MARK, index, text-boundary, tokenized-text, and city-image request blocks;
their pathnames differ between the floppy pair and 800 KB release. The F/G/H
write blocks, seventeen Pascal filename records, and their pointer tables
also have semantic labels. Four loader-state bytes and two S2 record indexes
previously shown as `BRK` instructions are now declared as data.
The boot loaders now name their A/B (and, in the 800 KB release, Z) file reads,
auxiliary-memory copy, RAM-disk check and warning, message printing, keyboard
read, file close, display setup, and mutable file-index/error-code bytes. Their
main flow now names memory setup, prefix selection, the two module-load groups,
error reporting, and return to ProDOS. The A/B/Z OPEN and READ blocks, the
CLOSE/QUIT blocks, and the Pascal paths for `/ram/` and the game prefix have
symbolic labels at their call sites.
Both boot listings now name the zero-page backup, language-card copy,
alternate-memory probe, module-copy loops, resident C installation, and
zero-page restoration on error. Unused address aliases generated from message
bytes have been removed from their headers.
The /ram/ OPEN result, warning continuation, and A/B/Z file-load success and
failure paths now have named branches. The loaders request fixed read sizes
and accept status $4C before closing the file, matching their shorter stored
file lengths. Their text printer now names the character loop, centered
column calculation, and key wait.
Both boot listings also have two HGR-clear entries. The apparent `BIT $40A9`
between `LDA #$20` and `STA $C3` was a `$2C` skip over a second `LDA #$40`;
the source now shows page 1 and page 2 entries explicitly. The byte-fill
loop, retained speaker-delay helper, and unreferenced bit setter for the
table at $BF58 have named paths. The 800 KB image's skipped Z-call fragment
remains retained as bytes.
An `H` module-load failure in `N` calls its disk prompt routine, which saves
the drawing state, presents a message, waits for input, restores the state,
and retries. The floppy routine selects Side A/B and treats status $2B as a
write-protection warning; the 800 KB routine draws a generic insert-disk
message. Both `N` sources now name this path, its HGR page-copy helpers,
active-page selector, and key/button wait. `R` retains a similar floppy prompt
routine, but no local call to it has been identified.
The `C` module
begins with ten named JMP entry points used by the other overlays. They expose
string selection and copying, auxiliary-memory page copies, HGR span copies,
and text expansion. The resident routines now name their string-scan,
page-copy, HGR row and column, and pronoun-expansion paths instead of retaining
address-only branch labels. Their callers in `WORLD.SYSTEM`, `B`, `N`, and `R` use
the service names. Its two graphics
copy entry points at $D2FB and $D327 use opposite auxiliary-memory switches.
The text copier at $D36E expands a `#` placeholder into an embedded "she" or
"he" string, which is now declared as data rather than disassembled as code.
Six four-entry parameter tables at $D2C2-$D2D9 are now data, and the true
`STA $97` at $D2E9 is restored. They select each span's first row and column,
exclusive end row and column, and linear buffer address. The setup routine
and scanline-address helper now have named call sites. The 192 low and 192
high bytes at $D600 and
$D6C0 are now generated from the Apple II HGR scanline address formula, rather
than presented as instructions. The preceding pages at $D400 and $D500 are
the byte-column quotient and bit-position remainder for twice an 8-bit
horizontal coordinate divided by seven, with values 140–255 interpreted as
negative; their formulas also regenerate the original 512 bytes. The 48 bytes
at $D780–$D7AF are two 24-entry tables for displaying hours 0–23 as 12-hour
clock digits; both `N` revisions now name their reads from these tables. `Q`
has been reviewed end to end. The larger game listings remain largely
mechanical.
Both `N` revisions now also identify the HGR rectangle fill and clear
routines at $7AEE and $7B70. Their four seven-byte endpoint mask tables are
data; two false instruction sequences in that region have been restored to
`JSR` and `CMP` instructions. Another self-modifying `JSR` at $65BA selects
one of three animation routines using parallel low- and high-byte tables;
the instruction, tables, and target entries are now explicit in both sources.
The main $6000 entry, new-detective registration, F-roster lookup, record
creation, and case-start path have matching semantic labels in both releases.
Registration's C reserved-name check and G hall-of-fame comparison are also
named in both sources. The shared `n_ui_text_ids.inc` gives readable names to
the C interface-string indexes used in registration and the case announcement.
The name-entry loop now identifies printable-character acceptance, deletion,
Return validation, rejection of an empty or space-led name, and the full-name
limit. Its search names the reserved, hall-of-fame, and 13-slot F-roster
iterations; a new record copies sixteen name bytes, clears rank and case
status, and saves F. The case-start branch separately names ordinary suspect
selection and the late-rank Carmen case.
Both `N` listings now identify the helpers that select those strings, append
them at the $A000 text buffer, draw them on the HGR page, and present the
completed text.
The arrest outcome path compares the selected warrant suspect at zero-page
$17 with the actual case suspect at $00. It has separate reports for a missing
warrant, a wrong warrant, a missed deadline, and a correct arrest. A correct
arrest increments the solved count and uses the rank thresholds for promotion;
catching Carmen also enters the hall-of-fame retirement path. Both revisions
now name these branches and the messages they select.
The arrest scene runs two moving-glyph stages on alternating HGR pages, then
selects a different frame loop for the matching or mismatched warrant. The
frame loops cycle a five-step phase and move their glyph positions each pass.
After a normal arrest, the report prints either the recorded-success message
or the new rank, followed by the number of cases until the next promotion.
The next-case prompt stores the yes/no choice and returns to the main entry.
The wrong-warrant and no-warrant reports also reach that prompt after their
separate failure messages.
The name helper at $81F2 compares the input name at $9E60 without ASCII case
sensitivity and returns carry clear for a match. The bounded random helper at
$83ED returns a value below its A-register bound. Case setup reads J's route
destinations at $9F00 and its per-city offsets at $9FD8; the helper at $7F9F
returns the current city's outgoing route count in X.
The case state at zero-page $00–$11 now names the suspect, route index and
reversed city route, hideout city, and current city. Setup chooses a random
hideout and stores it at the final route slot, then walks outgoing J edges
backward toward route slot zero for rank plus three steps, retrying candidates
already in that route. Slot zero becomes the case's starting city.
The travel code advances
the route index when the player follows the planned next city. The helper at
$6B99 returns carry clear when both the planned next city and current city
equal the hideout city.
The route loop now names its duplicate-city scan and the no-exit restart,
which sounds three short tones before restarting case setup. The opening
announcement names the news flash, gender-dependent pronouns, and the
weekday plus 12-hour deadline assembled from C's text and clock tables.
The next `N` path now names city-menu preparation, S2 clue selection, city
screen drawing, travel destinations, the selected-city move, and the three
investigation choices. The travel branch increments the planned route index
only for the expected next city, excluding the final hideout.
The selected-place path now distinguishes an incomplete route, the planned
route city, and the final city. At the final city, one of three place slots is
marked with value 1. If it is the first place investigated, that mark can move
to another slot by incrementing its $FF value to 0; a later visit to a marked
slot enters the arrest sequence. The place-clue builder treats $FF as no extra
clue. Earlier in city setup, each place independently has a chance to receive
one of the culprit's hobby, hair, feature, vehicle, or food traits. The
generator retries trait choices until the corresponding offset list has an
entry, then stores the trait value in the high nibble and its category in the
low nibble of the place-state byte. The clue builder uses that category to
choose one of five offset lists and the trait value to select a group within
it. Both release listings now name the generation, result, and return paths.
The travel menu also names the four-row mask loop that clears the current
city's map marker before the player chooses a destination.
The travel animation now names its two-axis integer line stepper. It compares
the absolute horizontal and vertical city-coordinate deltas, patches four
step opcodes to increment or decrement the coordinates, and clears a
two-row HGR stroke at each point. Both sources now use route-specific scratch
aliases for the working and destination coordinates, absolute deltas, error
accumulator, delay, and plotted-point count. The error starts at half the
major delta and advances the minor axis whenever the accumulated minor
delta reaches the major delta. The counter includes both endpoints, and
the caller charges `1 + floor(point_count / 4)` case hours for the trip.
The destination list walks the current
city's J route entries. An earlier page selector in this region displays
page 2 when $74 is odd; the later active-page selector uses the opposite
parity, so they retain distinct names.
The main city menu now uses named C text indexes for See Connections, Depart
by Plane, Investigate, and Visit Interpol; the connection toggle draws the
See/Hide choice separately. The four menu rows and three investigation rows
are named tables in both revisions. After text drawing, the renderer stores
pixel endpoints at $9E70/$9E80 and inverts an eleven-row rectangle between
them, masking the first and last HGR bytes so nearby pixels remain intact.
The city-description formatter now names its source and destination cursor
loops. It copies selected text from $0E00 to the $A000 text buffer, expands
high-bit bytes through C's word dictionary at $D7BD, and substitutes the
culprit's subject, possessive, or object pronoun for `#`, `@`, or `^`.
It inserts a space after a dictionary word unless punctuation or NUL follows,
then preserves a closing quote or adds a final period before drawing the
sentence on the HGR page.
The other city action opens the Use Computer / Save Case menu. Saving shows a
confirmation prompt and calls the existing H/F case-save routine on Return.
The computer displays six suspect-trait rows. Selecting a row cycles its
filter value, with $FF meaning unset. Its seventh choice compares those six
filters against every row of the ten-suspect trait matrix, stores matching
suspect indexes at $9EB0, and shows either no match, a candidate list, or a
single name. A single match writes the selected suspect to the warrant byte.
The drawing routine at $7C2F also has eight patched immediate operands, now
shown as `LDX`, `LDY`, and `LDA` instructions instead of false `BRK` bytes.
Other split `LDA`, `LDX`, and `LDY` immediates in `N` have been restored as
instructions with labels on their writable operand bytes. The helper at
$7D20/$7D23 similarly patches an `ADC` immediate. Four control-bit constants
at $7F25–$7F28 are read through `BIT`; the previous listing falsely showed
their $40 byte as `RTI`.
Both `N` revisions call the ProDOS MLI QUIT function at $6BBB. Its inline
function byte and pointer now lead to an explicit seven-byte parameter block
at $6BC4, matching the QUIT layout already identified in `WORLD.SYSTEM`.
The two HGR-page clear entries and two row-advance entries use a `$2C` BIT
opcode to skip an adjacent `LDA` immediate; their labels and skip behavior
are now explicit.
Both `N` sources also declare the six clue-category pointers, count limits,
text offsets, five clue lookup lists, and the 10-by-6 suspect trait matrix as
data. The matrix is indexed by suspect and category during clue generation
and warrant matching. The rank promotion and progress case counts are explicit
tables in both revisions, along with named clue-category tables. The 800 KB
source previously rendered two case-count pairs as false `ORA` instructions.
`N-suspect-traits.json` joins its values to the suspect
names and clue labels in `C`; the two releases contain the same traits.
The following region in each `N` revision is now classified as data. It
includes paired HGR stroke-clear masks, display and clue-text positions, seven
low-bit fill masks, and short drawing patterns. Three parallel mode tables
select a pattern, size, start coordinate, and six signed coordinate changes;
the middle mode alternates between two patterns. Further small lookup values
in that region remain unclassified.
The investigation menu now names the three-choice drawing loop, centered
place-title loop, and selection animation in both `N` revisions. The animation
uses the selected mode's six coordinate changes to prepare six bitmap strokes,
then plays a short speaker tone after each stroke. Its middle mode alternates
between the two three-byte patterns above.
The place visit path randomly patches a `JSR` operand with one of three
animation entrypoints. Those entries and their frame loops are named in both
`N` revisions. A separate route-city event chooses between two more frame
loops; the selected glyph indexes and coordinates remain visible in source.
The nearby city helpers now identify the map-position lookup used by travel,
the two nested-loop delay entries, and the investigation panel reset. The
place-clue text builder selects `She` for suspects 0–4 and `He` for suspects
5–9 before expanding the place description.
For travel, the selected menu row indexes the current city's destination
list in J. The destination city's position triple supplies the HGR column
and scanline for the map marker and the start or end of the route line.
The adjacent city-indexed table supplies route X coordinates in two-pixel
units, rather than indexes into the triples. All thirty values equal
`floor((7 * byte_column + bit_offset) / 2)`. The route plotter converts them
through C's doubling quotient/remainder tables, so odd pixel X anchors have
their route endpoint one pixel to the left. Both releases'
`N-city-map.json` views join the raw positions and route coordinates to the
city names extracted from C.
The `N` sound player reads twelve speaker tracks through a pointer table.
`tools/speaker_audio.py` executes the stored N/R player and delay instructions
to record timed speaker toggles, including their self-modified rest access to
$0030. Its limited interpreter rejects any unsupported opcode. Extraction
now writes WAV previews for all twelve N tracks and both R tracks in each
release, plus cycle counts, toggle counts, and duration metadata. These are
listening previews at a declared 1 MHz clock with interrupts disabled and a
50 Hz high-pass filter, not recordings of a specific machine's speaker.
The focused interpreter checks run with
`python3 -m unittest discover -s tools -p 'test_speaker_audio.py'`; they verify
the two-counter toggle count for a 256-tick note, the silent rest path, and
the sound-disabled return against the actual player bytes.
Each track contains period-table indices, duration changes marked by bytes
$80–$FE, and a final $FF. A zero period is a rest. Both revisions now assemble
the same labeled sound data from `src/shared/n_sounds.inc`; the extracted
`N-sounds.json` views list each track's note indices, loop periods, and
duration commands. The precise output frequency depends on the player loop
and machine timing, so the view does not assign musical pitches.
The general keyboard dispatcher accepts Control-D/F/L/Q/R/S/T/V for delete
detective, Hall of Fame, roster, quit, restart, sound toggle, joystick toggle,
and version screen. Both revisions now express all eight split target-address
table entries through handler labels. Short feedback tones
patch the delay operand at two entries; with sound disabled, the helper
spends the delay without toggling the speaker.
The version, deletion, Hall of Fame, and roster screens share a modal HGR
helper that saves display state, clears the next page, and restores the prior
view when the screen closes. Detective deletion builds a selectable roster
list, refuses to delete the detective currently signed in, and clears the
chosen 19-byte F record before saving F.
The roster renderer walks all thirteen F slots, draws each occupied name,
rank, and solved-case count, and stores the occupied slot indexes for the
deletion menu. It uses a two-row HGR rule drawer and an $FF-terminated glyph
writer, now named in both revisions. The 800 KB sound player uses the same
named command and period loops as the floppy version.
Immediately after those tracks, both `N` releases share 52 bytes of parallel
glyph-placement arrays. The three groups contain four, four, and five
placements; each placement supplies an HGR byte column, bit offset, row, and
glyph index. The following picture tables are also byte-identical in both
releases and assemble from shared includes. The final 366 bytes in each `N`
file are now split into six still-unclassified values and a 360-byte city
clue-count table. The table has thirty twelve-byte rows in C's city order;
both releases share the same data, assembled from
`src/shared/n_city_clue_counts.inc`. The six preceding bytes have no direct
pointer in the three-entry drawing-step pointer tables; the animation loop
reads exactly six bytes from each selected step table. Their role remains
unknown. The selector sums one row, draws a
uniform text offset, maps it to a category through cumulative counts, rejects
categories already chosen, and copies three text choices. It skips the first
three city-description strings when indexing the S2 text. Its count row uses
the planned route city, while the displayed city record comes from the
current city. For 27 cities, the row sum plus three equals the S2 text-line
count; Bangkok has three extra lines, London two, and Tokyo nine. The selector
does not reach those extra lines, though other code may use them.
`N-city-clue-counts.json` under each release's decoded assets joins the twelve
groups to their S2 text lines and lists lines outside this selector. The
editable ca65 count table remains the build input.
The next 182 bytes in each `N` release are explicit lookup tables: seven HGR
pixel masks; eight key codes and the low/high target bytes for their patched
`JSR`; thirty HGR position triples; thirty city-indexed route X coordinates;
three text-centering offsets; and two seven-byte HGR clear masks. An
unreferenced fourteen-byte sequence with values spaced eleven apart is kept
as a separate table pending identification. Only four bytes in this region
differ between releases, reflecting shifted code targets in the patched-call
table. The false `BRK` bytes of that call are now shown as `JSR $0000`, whose
operand is filled at runtime.
Another false-code region near $86B6 in the floppy `N` source now shows four
six-entry rectangle-parameter tables and two dialog option codes. The 800 KB
source has the same tables at $867D, with one different parameter, followed by
an explicit save-dialog message at $86B1. That message uses $8D for line
breaks and $81/$82 for special glyphs. `N-save-dialog.json` stores the message
as editable text and control-byte segments; the extractor round trips its
exact 60-byte extent, and the builder generates its ca65 include from that
view. The floppy source also restores a
split `STA` at $86F7; the 800 KB source restores two split `JSR` instructions
at $6162 and $6873, including the `BCS` that follows the first call.
The `R` intro overlay contains a second player with two tracks. Its period
table and commands match `N` tracks 0 and 9 exactly. Those bytes now assemble
from `src/shared/r_sounds.inc`, and `R-sounds.json` exposes both tracks. The
entry and replay loop, HGR-page clearing, frame display with input polling,
and game handoff now have named control points in both `R` listings.
The page display helper selects the active HGR page, copies its full 8 KiB to
the other page, and checks input. The two page-clear entries, T-frame drawing,
speaker-track player, randomized noise effect, and timed input polling also
have named entries.
The top-level sequence now names the S image pointers and phase entries:
Broderbund logo and moving figure, five T frames, ACME storefront and case
prompt, globe with an airplane glyph, and title image with credits. The four
intro text indexes are symbolic. The two releases contain byte-identical `R`
files, so the 800 KB listing includes the floppy source. The HGR RLE renderer
now names its six header fields, literal and repeat paths, scanline/column
advance, two-pass exit, and active-page row-address helpers. A zero repeat
count yields 256 copies through its decrement loop. The moving-glyph, T-frame,
and globe animation loops now name their frame and position branches.
Control-S toggles sound during the intro; another key or either joystick
button enters the game. Its bounded random helper has the same generator
shape as `N`'s helper. The input poll now names its keyboard and joystick
paths. The two intro sound tracks use duration commands, period-table notes,
and a zero-period rest that redirects the speaker access away from $C030;
their command and oscillator loops are labeled. The moving-glyph accent and
the two randomized noise groups also have named timing paths.
The intro overlay's HGR rectangle fill and clear routines now have named entry
points and four explicit seven-byte endpoint mask tables; their split `JSR`
and `CMP` instructions were restored. Four six-entry rectangle-coordinate
tables and the five 750-byte `T` frame pointers are now explicit in both `R`
sources. The character lookup branch and several self-modifying immediate
operands were also restored from false instruction boundaries.
The fill and clear rectangle loops now name the first-byte mask, middle-byte
write, last-byte mask, and scanline advance. Their small helpers set or clear
the spilled bit in the next HGR byte when an endpoint lands at pixel position
six. The six-row rectangle-frame caller now names the immediate operand bytes
it patches for the inset and outer edges.
The eight custom bitmap glyphs at the end of `R` use the same packed format
as `T` and `U`. The split pointer table at $6C35–$6C44 selects character codes
$8B–$92; its pointers and the glyph records agree exactly. The extractor
checks that decoding and re-encoding the complete $6CDE-onward suffix
preserves every byte, and writes `R-glyphs.json` with eight PNG previews for
each release. The builder generates a labeled ca65 include from the editable
JSON rows, and the pointer table resolves to those labels. The four preceding
NUL-terminated intro strings are now declared as text rather than false
instructions. The nearby keyboard routine patches a `JSR` target from split
low/high tables, now shown explicitly. Its active comparison is for control-S
($13): it calls a no-op and returns carry set so the caller waits for another
key. The table also stores a sound-toggle target, but the local dispatcher
initializes its index to zero and has no identified path to that second entry.
The separate intro input poll accepts another key or either joystick button.
The keyboard reader at $6605 preserves the original seven-bit key in A,
places its uppercase ASCII form in $77, and consumes the dispatcher key before
returning.
Additional false instruction boundaries
in the `R` listing were resolved to `INC $74`, two zero-page `STX` operations,
`LDY $72`, and a `BIT $C030` followed by `LDA #$1F`.
The intro renderer now names its string selector, glyph lookup, dimension
reader, glyph drawing, and text-layout entries. Character codes $20–$8A use
the `D` font pointer pages at $B900 and $B970; $8B–$92 use `R`'s own pointer
table. The string selector passes the address of the four declared intro
strings to `C_SKIP_NUL_STRINGS`.
The adjacent `$6395` helper selects a string using Y and tail-calls C's
string-copy service. A scan of absolute address operands in the extracted
game files found no direct caller, so its runtime use remains unknown.
Three other retained entries now have explicit names and input comments:
`B_COPY_WHOLE_PAGES` at $989A copies A pages from source page X to destination
page Y under the caller's memory mapping (A zero copies 256 pages);
`R_DEFAULT_FEEDBACK_TONE` at $63B8 supplies ten toggles and delay $50 to the
existing tone helper; and `R_DRAW_ZERO_PAGE_RLE_IMAGE` at $6B35 supplies Y=0
to the RLE renderer, making X a pointer into zero page. A scan of direct
JSR/JMP byte patterns across both releases' executable files found no calls
to these three addresses. Indirect or computed entry remains possible.
The renderer's glyph path now names its seven-pixel source-byte count,
bitmap draw, and destination-column arithmetic. Its string path scans and
measures each line before drawing, backs up to a space at the right edge,
then resumes with the next word. A control byte at or above $8D resets the
horizontal position using $91; $8F also uses $92 before the next line.
The direct pointer entry and reverse-column helper have no identified local
callers, so their external use remains uncertain.
The adjacent centering routine now names its width-measure loop and
half-width subtraction. It uses C's $D400/$D500 quotient/remainder tables to
convert the requested X position into a byte column plus one of seven pixel
positions. When $68 is nonzero it also stores a derived X value at
`$9E70+$94`; no reader of that value has been identified in `R`.
The adjacent bitmap routines now distinguish direct row copies, a row-window
copy, a clipped glyph copy, and the clipped XOR glyph path used by intro
animations. The glyph paths shift source bits through the $B2xx lookup pages,
mask the left and right edge bytes, and advance the HGR row after each source
row. The direct copy entries have no identified local callers.
The retained `R` disk-prompt service also has no identified local caller. It
passes indexes such as $61 and $75 to the intro string selector, although
only four NUL-terminated intro strings are declared before the glyph data.
The service's intended text source remains unresolved; the stored disk-side
indexes $06/$07 and a separate unreferenced prompt fragment have the same
question. Its surrounding page-display, input, and bounded-random branches
now have descriptive labels.
The remaining address-only local labels in `R` have been replaced with
descriptive names or removed when they had no references. This does not
resolve the unreferenced prompt fragment or establish all external entry
points.
The corrected 65816 region, SmartPort slot-ROM signature table, and inline
request bytes in `Z` are verified byte-exact, but the module is not fully
reviewed. The [Apple IIgs Firmware Reference Manual](https://www.brutaldeluxe.fr/documentation/cortland/v2_01_AppleIIGSFirmwareReferenceManual.pdf)
documents the SmartPort commands and UniDisk 3.5 control-list layouts used to
identify its STATUS, READ BLOCK, CONTROL, SetAddress, DownLoad, and Execute
requests. The STATUS buffer contains the device count or a device information
block, depending on the requested status code; its type and subtype bytes
select the subsequent device path. The UniDisk path sets controller address
$0500, downloads a 101-byte 65C02 routine at $43B0–$4414, and supplies its
initial A, X, Y, P, and PC through the Execute list.
Its late disk scanner now shows three self-modifying `LDA absolute` reads and
their `BPL` wait loops as instructions. One routine resets their operands to
the Disk II data register at $C0EE; another patches all three addresses from
registers A and Y. The scanner looks for the byte sequence D5 AA 96 and
counts matches through $E5. The downloaded routine has a carry-clear zero
result and three carry-set status returns ($30, $31, $32); its two `$2C` BIT
bytes intentionally skip adjacent `LDA` immediates. How the routine's disk
scan and later transfer interact with the controller still needs analysis.
The AppleDisk $05/$06 calls correspond to SetHook/ResetHook in the
[Apple IIgs Firmware Reference Manual](https://www.brutaldeluxe.fr/documentation/cortland/v2_01_AppleIIGSFirmwareReferenceManual.pdf).
The stored SetHook reference $82 is outside that draft manual's $01-$07
table. The ResetHook list declares four payload bytes rather than the
documented one; the extra bytes overlap the UniDisk Execute list. Their
actual firmware interpretation remains unverified. The three list addresses
supplied to the CONTROL wrapper at $40A4 are labeled; $43AE is the DownLoad
byte count, rather than the start of the instruction stream.
The byte $38 at $43AD is outside the SetAddress list's declared two-byte
payload and before the DownLoad pointer; no reader of it has been identified.
The wrapper entries for inline firmware commands $00, $01, and $04, the slot
ROM probe and patched jump, and the fourteen-byte $E0–$ED scratch-state swap
are now named in the `Z` source. The inline-byte helper advances the caller's
return address by the supplied count before returning.
The remaining local branches in `Z` now name the slot/device search, signature
comparison, block-index calculation, disk prologue scans, and error/return
paths. The three self-modifying byte-port operands have separate low/high
labels. The downloaded program's calls to controller addresses $72 and $7B
are identified as controller firmware entries, but their precise services
remain unverified.
The block-index routine at $4171 can be described without assigning physical
meanings to its two input fields. For field 7 in 0–79, define
`count(t) = 12 - floor(t / 16)`. It returns
`2 * sum(count(t), t = 0 .. field7 - 1)`, plus `count(field7)` if field 8
is nonzero. The five-byte table covers only those eighty input values;
larger values index into the following code. This produces base indexes
0, 384, 736, 1056, and 1344 at field-7 values 0, 16, 32, 48, and 64.
The exact physical meaning of those fields remains unverified.

The downloaded 101-byte program moves from host $43B0 to controller $0500.
Its internal branches are relative; its two absolute JSRs target controller
firmware. It stores input A at $14, moves input X bit 1 into $16 bit 7,
and uses input Y as the number of prologues to consume. Carry set from $7B
returns status $32. Its pre-decremented $30 retry counter permits at most
47 calls to $72; exhausted retries or a mismatch between $14 and
`(($29 & 2) << 5) | $2B` return status $31. A nonzero $2A retries the read.
The shared scanner consumes D5 AA 96 matches until $E5 reaches zero.
Its mismatch counters eventually fall through to the AA poll when both wrap,
without requiring a preceding D5. They do not branch to the retained status
$30 entry, which has no identified incoming branch. These are observations
of the stored instructions, not verification of the controller services.

`Z`'s entry reads eight inline bytes through the saved caller return address;
bytes one and two select the block buffer, bytes three and four supply a block
index, and bytes five and six point to a NUL-terminated signature. The routine
compares that signature with the block data starting five bytes into the
buffer. Bytes seven and eight feed its disk-scan and block-index setup. The
skipped loader fragment at $20BF contains a `JSR $4000` followed by one such
eight-byte record (buffer $0800, block $0002, signature at $2300). That
fragment has no local incoming control flow; its argument records and result
checks are shown as inactive source rather than treated as an active call path.
Asset formats beyond the identified text, HGR images, sprites, font, and S2 text sections
remain to be decoded. The supplied
`carmen-world.pdf` metadata identifies it as a scanned CoCo manual;
`carmen-world-iigs.pdf` describes an Apple IIgs version, so neither is treated
as authoritative for this Apple II program's internals.

`tools/emit_source.py` can generate a first-pass listing for newly classified
code files. It keeps existing listings by default; `--force` replaces manual
work. The status of the project should be judged by both file-level checks
and the unresolved analysis above.
