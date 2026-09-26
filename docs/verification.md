# PRD deliverables and verification

This audit follows the three outputs in [PRD.md](../PRD.md). It distinguishes
reconstructing the supplied game from establishing every dormant routine or
physical device behavior.

## Disassembled source

All thirteen executable game-file instances have ca65 sources: WORLD.SYSTEM,
B, C, N, Q, and R in both releases, plus Z in the 800 KB release. C, Q, and
R are shared between releases. The sources have descriptive labels, named
entry points, inline-call data declarations, explicit tables, and comments
for memory mapping and self-modifying operands. The
[source guide](source-guide.md) explains the modules, case bytes, renderer,
and assembly conventions. No assembly source hides executable bytes with
`.incbin`, and no address-only `Lxxxx` labels remain.

Assembly is required for files classified as code; a missing source fails the
build. All thirteen assembled files match their corresponding original bytes
through EOF. This proves reconstruction fidelity. The annotations and guide
provide readability; byte equality alone would not prove it.

## Extracted assets

Every valid source-directory file has an exact binary extract and hash in
`reconstruction/manifest.json`. The thirty game-data file instances build
from decoded data, editable structured sources, or the established E-table
formula. Assets embedded in executable modules are likewise separated as
strings, tables, or generated includes.

The extracted views cover dictionary and world text, interface messages,
city names and route graphs, suspects and clues, saved detective/case records,
HGR pictures, fonts, icons, sprites, and speaker tracks. Both releases have
30 city records and landmark previews, 920 decoded world-text lines, 107 font
glyphs, and 14 WAV listening previews. Original compressed streams and
unclassified trailing bytes are preserved without inventing meanings for them.

ProDOS and Finder metadata are retained external dependencies: two ProDOS
files and three Finder files. Their bytes are also included in the image checks.
They are not substituted for reconstructed game code or decoded game assets.

## Build and check

`make build` creates the two 140 KB floppies and the 800 KB image.
`make check` rebuilds and checks all 48 file instances: 21 on disk 1, two on
disk 2, and 25 on the 800 KB image. It checks original-image hashes, complete
root-directory coverage, volume names, declared file counts, file bytes,
EOF, ProDOS type, and auxiliary load address. Rebuilt directories reject
the malformed unused entry present on the original disk 1.

The latest isolated check began with only the three original disk images,
current `src/`, `tools/`, and Makefile. There were no extracted assets,
manifest, or prebuilt outputs. `make extract` generated the current asset
schemas, including animation glyph indexes; `make check` then passed for all
48 files. This establishes that regeneration does not depend on prior build
artifacts or manually prepared decoded views.

`make test` runs nine focused tests for snapshot encoding and interpretation,
directory coverage and count failures, and execution of the stored speaker
player bytes. All nine passed during this audit.

## Runtime evidence and practical limits

The rebuilt floppy pair has booted and exercised travel and investigation in
Apple2TS; MAME has also run the pair. The rebuilt 800 KB image has booted,
registered detectives, displayed city data and clues, and saved/resumed one
rookie case across an emulator boot. The
[save/resume record](runtime/po-save-resume.json) confirms the exact snapshot,
zero-filled H-page tail, roster flag transitions, and the intentional menu
selection reset on resume. Private sessions were stopped after their checks.

These checks do not establish a complete successful case, every disk-swap or
write-protection path, physical SmartPort/UniDisk operation, or audio output
from a real machine. The WAVs are timing-based listening previews. Specific
semantic uncertainties remain in retained data, dormant entries, and Z's
firmware interactions; they are listed in the
[reconstruction notes](reconstruction.md#current-reverse-engineering-limits).

The rebuilt images preserve every valid file and its required metadata. They
use fresh filesystems, so timestamps, allocation, boot/filesystem structures,
and unused space can differ from the original images. Whole-image byte
identity is not claimed; the PRD permits a reconstructed image without
requiring identical container bytes.
