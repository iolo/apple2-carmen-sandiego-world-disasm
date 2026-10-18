# Human approval and production build

The reviewed catalog is frozen at SHA-256
`e1a3ccaa468b8df7501e82408c15cc1cb452e1f082787ea9d704b1cb65118195`.
Its [review bundle](review/e1a3ccaa468b/index.html) includes all 1,287 targets,
context, source references, protected tokens, glossary, editorial notes and
105 offline font previews. The user explicitly approved the whole catalog,
including the final i.040 wording. [Conversation evidence](approval-evidence.json)
records the exact response and scope confirmation;
[`approval.json`](../../assets/korean/approval.json) pins the approved version.

PLAN-korean.md K3 requires explicit approval of the entire version before
real translations are applied to game media. Technical checks and silence
cannot supply that approval. Corrections remain draft work and require a new
catalog hash, rebuilt evidence as necessary and another review.

## Receipt

`assets/korean/approval.json` is a separate receipt. It records the human
reviewer, timezone-qualified approval time, exact human response, full sorted
target-ID set, catalog SHA-256, bundle SHA-256 and review-manifest SHA-256.
The frozen catalog keeps its reviewed bytes, including the historical `draft`
status labels and unset embedded approval field. The external receipt is the
authoritative approval state; editing the catalog to add receipt metadata
would invalidate the reviewed hash.

Only after the human actually approves the whole version, preserve their
exact response in a local UTF-8 file and record it:

```sh
python3 -m tools.korean.approval record \
  --review-manifest docs/korean/review/e1a3ccaa468b/manifest.json \
  --reviewer HUMAN_REVIEWER \
  --statement-file PATH_TO_ACTUAL_HUMAN_RESPONSE \
  --all-translations
python3 -m tools.korean.approval check
```

An agent must not invent the response or run `record` merely because tests
pass. The command validates the bundle; it does not independently establish
that a human authored or intended the supplied statement. The session's
explicit human response is the authorization evidence.

Every production entry point checks the receipt before creating production
output. A missing receipt, incomplete ID set, unresolved issue, changed
catalog/glossary/review notes/font metadata/license, changed review artifact,
or changed approved manifest rejects the build. A later catalog edit also
invalidates an old external receipt, even if its file remains for audit.

## Build

```sh
make korean
```

The command builds
`build/korean/approved/carmen-world-ko.po`. It regenerates original debug maps
from source rather than requiring cached maps. The existing compiler emits
literal approved text instead of the synthetic permutation, including clock
words and bitmap captions. It preserves the English input guard, TEXT MODE
messages, original compressed pictures, game IDs and save layout.

The image assembler checks the reviewed synthetic baseline, every production
file's measured footprint, fixed addresses, 16/24-bit lengths, original
inputs, all 27 ProDOS payloads and metadata, normalized dates and repeated
build identity. It rechecks approval before publishing the completed image.
No RAM/disk alternative is introduced if a bound fails.

The manifest records the exact approval receipt and input hashes. Repeating
the command with the same inputs must produce the same disk SHA-256.
`make korean-synthetic` remains the separate preapproval experiment.

`make korean-image-check` verifies the completed pristine approved image
without rebuilding or writing it. It checks current source/font/approval pins,
the whole disk, all 27 payloads and ProDOS metadata, all 1,286 translation
targets in the 800K edition, independent BDF font bytes, English exclusions,
caption pointers/data and every S2 text/picture/index/buffer bound.
`make korean-synthetic-check` runs the same data checks on the synthetic disk.
These commands check pristine release media; legitimate F/G/H changes on an
emulator's writable copy belong to the separate save audit.

## Verified build and runtime scope

The approved image SHA-256 is
`890fca81bd99fcdd747b594536781d4c7ce8c52e82fb443fcd4939a0c913eeda`.
Repeated local builds and two builds in a fresh temporary source copy produce
identical bytes. The temporary copy excludes the entire build directory and
runs the read-only verifier after rebuilding; see [clean-build.json](clean-build.json).
All 27 payloads and metadata, all 1,286 800K targets, every S2 record and original
picture, and independent font bytes pass [approved-image-check.json](approved-image-check.json).
The image has 1,179 free ProDOS blocks; all measured RAM bounds fit.

The six suites under [`runtime/approved/`](runtime/approved/) exercise literal
approved text: boot/registration/computer/investigation/travel/save/cold restore,
all-glyph C/N readers with both pronoun cases, 31 clock cases, captions on both
pages, message extrema, and 60 native city reads. Their approved reports use
`mode`, `image_sha256`, `catalog_sha256` and `approval_sha256`. The synthetic
reports and their frozen review schemas remain separate.

[Save transfers](runtime/approved/save-compatibility.json) cold-restore native
English saves in Korean and Korean saves in English, then investigate and
travel. [Disk-error tests](runtime/approved/disk-errors.json) recover actual
missing-file errors using owned replacement media; TEXT prompts remain English
and HGR prompts render Korean, with font and resident code intact after retry.
Gameplay branch and visual evidence is indexed in [progress.md](progress.md).

The approval gate rejects missing, stale, partial or unresolved receipts.
The original release baseline records 34 passing unit tests. The read-only checker's temporary corruption probes
reject five independent byte/length/metadata/source/font changes, including a
font corruption with recomputed outer hashes. These tests never invent actual
human approval. See [image-check-rejections.json](image-check-rejections.json).

The final editorial decisions preserve the original Priam object and the
user's implicit-meaning (?) marker for i.040; no explanatory medical gloss is
inserted into the game. Older review snapshots are preserved byte-for-byte in `review/history.tar.xz`;
the current approved snapshot stays directly accessible.
