# Save compatibility policy

The Korean implementation retains the original 800K edition's save layout,
English name input and numeric game IDs. Translation text, glyph IDs, font
data and translated display names are not added to F, G or H. A changed
catalog hash alone therefore does not define a new save format.

## Original format retained

| File | Size | Layout |
| --- | ---: | --- |
| F | 256 bytes | Thirteen 19-byte detective records, followed by nine untouched padding bytes. Each record has a 16-byte FF-terminated ASCII name, rank at +16, solved-case count at +17 and saved-case flag at +18. |
| G | 256 bytes | Sixteen 16-byte FF-terminated ASCII hall-of-fame names. |
| H | 3,328 bytes | Thirteen 256-byte pages, one per F slot. The first 33 bytes copy case state `$00–$20`; the remaining 223 bytes are zeroed on save. |

Case fields are defined in `tools/case_state.py`: suspect, route graph and
route slots, city IDs, day/hour/deadline, investigation count, warrant suspect,
sound, treasure index, menu selection and six numeric trait filters. The
ordering of cities, suspects, ranks, treasures and traits remains the original
800K ordering. Translated names are display data, not replacement identifiers.

`N_SAVE_CURRENT_CASE` writes H and sets the selected F flag.
`N_RESTORE_SAVED_CASE` copies all 33 bytes back, sets the menu selection at
offset `$1A` to 2, and clears that F flag. City preparation also resets the
investigation count at `$16` to zero. A fresh restore therefore changes
the disposable disk even when the player has not progressed further.
The original F/G/H sizes and these source routines are verified against the
original media; `runtime/synthetic-text.json` records the tested synthetic
save/fresh-boot behavior and exact padding/flag checks.

## Support policy

- **Same approved Korean build:** save and fresh-process restore are required
  release checks. They pass in `runtime/approved/synthetic-text.json` on the
  approved image, including all case bytes, padding and consumed resume flag.
- **Original English 800K edition:** the format and identifier ordering are
  retained for compatibility, and bidirectional cold-boot transfer tests pass in
  `runtime/approved/save-compatibility.json`, including investigation and planned
  travel after restore. No automatic player-facing import is currently offered.
- **Another Korean build:** compatibility requires unchanged F/G/H layout,
  numeric game-ID ordering and underlying world/route/trait data. Translation
  edits with the same state schema are intended to remain compatible. A future
  build changing those contracts must declare a new schema and provide an
  explicit migration before claiming compatibility.
- **140K floppy editions:** outside the first 800K Korean release. No save
  interchange with those editions is claimed.

Keep a copy before importing or resuming. F and H must retain matching slot
assignments: copying an H page alone can attach a case to the wrong detective.
Transferring the entire F/G/H set replaces the destination roster, hall and
case pages, so automated compatibility tests use only owned disposable images.
MAME machine save states are emulator artifacts and are not game-save files.

## Certification evidence

[`runtime/approved/save-compatibility.json`](runtime/approved/save-compatibility.json)
records both directions on the approved image
`890fca81bd99fcdd747b594536781d4c7ce8c52e82fb443fcd4939a0c913eeda`.
The English source is a normally registered detective with native investigation,
travel and save. The Korean source is the approved lifecycle's normally saved
case. Each destination is a fresh process using a pristine edition copy plus
only the source F/G/H payloads.

Both tests compare all 33 restored fields with the native menu/count resets,
the single consumed F flag, complete unchanged H including padding, unchanged G,
and all unrelated file payloads. Each then investigates and travels to the
actual planned route city. Source/destination image hashes, F/G/H hashes,
checkpoints and native HGR captures are archived with the report.
Reproduce with `python3 -m tools.korean.save_compat_test --tag NEW` after the
approved lifecycle suite. Tests use only owned disposable copies.

This certifies the tested original 800K edition and this approved Korean
build. Future Korean builds still require the schema/ID contracts above;
no emulator machine-state interchange or floppy save interchange is claimed.
