# Korean edition

The approved 800K ProDOS edition runs on a **128K Apple //e** (64K main and
64K auxiliary RAM). Build with `make korean`, then verify with
`make korean-image-check`. The image is `build/korean/approved/carmen-world-ko.po`;
play using a writable copy.

Detective names use ASCII, with the original 15-character and pixel-width
limits. Arrow keys, Return, Escape and Y/N retain their original behavior.
Hardware TEXT MODE messages stay English. The 140K Korean port is outside scope.
The user confirmed the image works in their own testing on 2026-10-19.

## Playing and checking the result

- [MAME Lua autoplay](autoplay.md): memory-assisted play from a new detective through Carmen's arrest.
- [Screenshots](screenshots/README.md): representative native screens.
- [Save compatibility](save-compatibility.md): English↔Korean 800K saves and the F/G/H format.
- [Release checks](release-checks.md): verified gameplay, visual inspection and coverage limits.
- [Build and approval](approval-and-build.md): reproducibility and exact-version approval.

## Understanding and improving the patch

| Area | Start here |
| --- | --- |
| Translation text and terminology | [Catalog](../../assets/korean/catalog.json), [glossary](../../assets/korean/glossary.json), [review notes](../../assets/korean/review-notes.json) |
| Text sources, protected tokens and exclusions | [Text inventory](text-inventory.md) |
| Encoding, font and readers | [Encoding](encoding.md), `src/korean/` and `tools/korean/` |
| RAM banks, buffers and file sizes | [Memory layout](memory-layout.md) |
| Running MAME tests or a Lua command | [Runtime workflow](runtime-workflow.md) |
| Completion and evidence map | [Progress](progress.md) and [requirement audit](plan-requirements.json) |

Translation changes require review of the changed catalog version before a
new approved image is built. The existing [approval receipt](../../assets/korean/approval.json)
pins the current [review bundle](review/index.html).

## Verification records

[Runtime reports](runtime/README.md) remain directly readable. Detailed captures
are in one indexed archive; [superseded review drafts](review/README.md) are in
a separate history archive. Their bytes and hashes are preserved. These files
are development evidence, not game assets or player saves.

```sh
make korean-release-check               # audit the recorded release evidence
make korean-reproduce                   # rebuild in a fresh source copy
python3 -m tools.korean.evidence check   # verify both evidence archives
```

The GalmuriMono7 source, pinned revision and OFL license are in
`assets/korean/font/`. The release includes the 710 used Hangul syllables.
