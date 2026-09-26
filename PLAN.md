# Carmen Sandiego Apple II reconstruction plan

## Objective

Produce human-readable disassembled game source, extract the game's assets,
and provide scripts that rebuild the supplied two 140 KB floppies and related
800 KB ProDOS release from source and assets.

## 1. Inventory and preserve the inputs

- [x] Inspect all three disk images and enumerate their valid files.
- [x] Extract original file bytes and retain their hashes and ProDOS metadata.
- [x] Record image versions, module addresses, and differences between releases.
- [x] Preserve ProDOS and Finder files as external dependencies.
- [x] Account for the malformed unused directory entry on original disk 1.

Artifacts: `assets/disk1/`, `assets/disk2/`, `assets/po/`, and
`reconstruction/manifest.json`.

## 2. Establish a reproducible assembly and image build

- [x] Represent WORLD.SYSTEM, B, C, N, Q, R, and the 800 KB release's Z as
  ca65 sources at their original addresses.
- [x] Share sources for the byte-identical C, Q, and R revisions.
- [x] Assemble executable modules and build all three ProDOS images.
- [x] Fail when an executable source is missing or its reconstructed size changes.
- [x] Verify all 48 file instances, including bytes through EOF, file type,
  auxiliary load address, directory coverage, and volume names.

Artifacts: `src/`, `tools/reconstruct.py`, `Makefile`, and the three rebuilt
images under `build/`.

## 3. Make the disassembly readable

- [x] Follow boot, module loading, intro, registration, and case control flow.
- [x] Replace mechanical address labels with descriptive routine and data names.
- [x] Separate identified strings, tables, ProDOS parameter blocks, and inline
  firmware arguments from instructions.
- [x] Restore identified instruction boundaries and name patched operands.
- [x] Annotate memory mapping, overlay lifetimes, graphics/text rendering,
  menu input, sound players, case generation, warrants, and save/resume.
- [x] Identify the mixed 6502/65C02/65816 regions in Z and document its
  SmartPort/controller paths and their uncertainties.
- [x] Explain persistent case fields and distinguish character codes from
  direct font/icon/animation glyph indexes.

Artifacts: annotated assembly, shared data includes,
[source guide](docs/source-guide.md), and
[reconstruction notes](docs/reconstruction.md).

Unidentified bytes and dormant routines remain explicitly described and
preserved. Their presence does not imply that an inferred purpose is proven.

## 4. Decode and expose the assets

- [x] Extract the dictionary, interface strings, names, clue labels, and world
  text, including the game's pronoun substitutions.
- [x] Decode all 30 city records and 920 world-text lines in each release.
- [x] Decode HGR pictures, landmark images, the font, icons, and T/U sprites;
  generate image previews and editable representations.
- [x] Decode route graphs, suspect traits, detective rosters, hall-of-fame
  names, and saved-case pages into structured views.
- [x] Extract speaker sequences and generate 14 WAV listening previews per
  release using the stored player instructions.
- [x] Rebuild identified assets from their editable sources, retaining exact
  original binary extracts for comparison.

Artifacts: `assets/decoded/`, the text and image source directories in
`assets/`, codec tools, and shared assembly data includes.

## 5. Verify regeneration and observed runtime

- [x] Run extraction and rebuilding in an isolated directory containing only
  the original images, current sources, tools, and Makefile.
- [x] Check all 48 rebuilt files against the originals.
- [x] Run nine focused case-state, directory-coverage, and speaker-player tests.
- [x] Boot the rebuilt floppy pair in MAME and Apple2TS.
- [x] Exercise travel and investigation on the rebuilt floppies.
- [x] Boot the rebuilt 800 KB image, register detectives, and display city/clue data.
- [x] Verify one 800 KB save/resume path across emulator boot, comparing case
  bytes, H-page padding, and roster resume flags.
- [x] Retain runtime evidence and stop private emulator sessions after testing.

Commands:

```sh
make inventory
make extract
make build
make check
make test
make smoke
```

## 6. Document the deliverables and their limits

- [x] Document dependencies, commands, asset formats, and source navigation.
- [x] Map the three PRD outputs to concrete artifacts and verification evidence.
- [x] Distinguish exact file reconstruction from whole-image byte identity.
- [x] Record remaining semantic and runtime uncertainties without claiming
  exhaustive gameplay or physical-hardware validation.

Evidence: [verification audit](docs/verification.md) and `docs/runtime/`.

## Further investigation

These items remain open beyond the delivered reconstruction and observed checks:

- [ ] Complete a successful case through warrant, arrest, and progress update.
- [ ] Exercise prompted floppy swaps, write-protection, and broader save/error paths.
- [ ] Verify persistence after exporting and remounting modified emulator media.
- [ ] Establish Z's remaining firmware-service meanings and physical
  SmartPort/UniDisk behavior.
- [ ] Identify retained trailing bytes and the intended use of dormant entries.
- [ ] Compare sound with physical hardware if hardware fidelity is required.

The rebuilt images use fresh filesystems. Allocation, timestamps, boot/filesystem
structures, and unused space can differ; whole-image byte identity has not
been established. See the reconstruction notes for the specific unresolved
regions and the verification audit for the scope of each recorded check.
