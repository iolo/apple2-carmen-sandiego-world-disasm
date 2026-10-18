# Approved 800K Korean release checks

The approved image is `build/korean/approved/carmen-world-ko.po`, SHA-256
`890fca81bd99fcdd747b594536781d4c7ce8c52e82fb443fcd4939a0c913eeda`.
It uses 128K Apple //e RAM (64K main plus 64K auxiliary), with 1,179 free
ProDOS blocks. The user-approved catalog is
`e1a3ccaa468b8df7501e82408c15cc1cb452e1f082787ea9d704b1cb65118195`.
[Approval evidence](approval-evidence.json) preserves the user's responses.

| Check | Evidence and result |
| --- | --- |
| Exact approved data and original exclusions | [approved-image-check.json](approved-image-check.json): all 27 payloads/metadata, independent font cells, every 800K target, S2 index/text/pictures and bounds pass; original inputs unchanged |
| Repeatable clean build | [clean-build.json](clean-build.json): two builds from a fresh source copy with no build artifacts match the local approved image exactly |
| Native approved text | Six reports in [runtime/approved/](runtime/approved/): literal Korean lifecycle, 710-glyph C/N reader coverage, both pronoun cases, 31 clock cases, captions on both pages, message extrema and 60 ProDOS city reads pass |
| Gameplay compared with English | [gameplay.json](runtime/approved/gameplay.json): all six trait inputs and unique warrants, full arrest animations/reports, no/wrong warrant, correct arrest, promotion, timeout and Carmen retirement pass through menus |
| Numeric state preserved | All 33 case bytes match between editions for every nonretirement paired outcome. Retirement saves the same rank 5/30 solved progress, adds the same ASCII name to G, removes the same F slot and returns to sign-in. Its subsequent randomized case-initialization bytes are not compared. |
| Native saves in both directions | [save-compatibility.json](runtime/approved/save-compatibility.json): English→Korean and Korean→English cold restores preserve fields, padding and unrelated payloads, consume only the native flag, then investigate and travel successfully |
| Recoverable disk errors | [disk-errors.json](runtime/approved/disk-errors.json): actual missing R and H files trigger English TEXT and Korean HGR prompts; mounting owned good media and native retry succeeds with intact font/code |
| English regressions | [english-baseline.json](english-baseline.json): `make check`, 34 unit tests and `make smoke` pass; the smoke covers the rebuilt floppy pair |
| Aggregate evidence | [release-check.json](release-check.json): image/catalog/approval identity, referenced artifact hashes, component font/library identity, 128K profiles and owned-process shutdown verified |

## Visual inspection

Native HGR bytes were captured at debugger instruction boundaries and rendered
as enlarged monochrome PNGs. Original MAME PNGs are preserved with them in
`runtime/artifacts.tar.xz`;
those can lag the last drawing instruction while paused. These are real game
screen bytes, distinct from the review bundle's offline font previews.

The following screens were inspected: title/credits, normal city and clock,
computer with all six traits, longest encoded city description, promotion,
timeout, retirement hall and recoverable HGR disk prompt. Korean glyphs remain
inside their panels with 8-pixel cells and the native line spacing. Text and
picture regions do not overlap, the ASCII detective names remain readable,
and the tested reports preserve every expected glyph and native scroll.

- [Longest city description](screenshots/long-description.png): the six-line Argentina description fits the right panel. This test pins a valid selected-description buffer from the current city's first three S2 fields, then redraws by normal computer exit. It does not claim that the random selector chose that field unaided.
- [All computer traits](screenshots/computer.png): six translated labels and values fit their original rows.
- [Promotion](screenshots/promotion.png): rank, remaining-case number and ASCII name fit the report panel.
- [Timeout](screenshots/timeout.png): suspect and next-case prompt remain readable.
- [Retirement hall](screenshots/retirement.png): translated title and the saved ASCII detective name fit the hall.
- [HGR disk prompt](screenshots/disk-prompt.png): all four prompt lines and Return instruction fit the modal rectangle.

The title and caption component suite additionally compares independent font
pixels, protected picture bytes, CPU registers/flags and zero page against the
unhooked decompressor. The original compressed S/O/P and all 30 S2 pictures
remain unchanged. No translation or font change was needed after visual QA.

## Scope and unplayed branches

This release does not claim exhaustive gameplay. Native-generated rank 0, 1
and 4 routes supply valid late-case F/H fixtures for paired cold boots. Their
menus, warrant evaluation, animations, reports, save writes and retirement
return execute normally; game instructions are not patched. During automation,
stale posted keys and the text-speed Open Apple button are allowed to release
in an idle menu interval before the next tested input.

Every random route/animation/clue combination, all name edits/rejections,
full-roster deletion/replacement, and full-hall replacement were not played.
All city/trait/message layouts are measured statically; native message extrema,
all-glyph readers, all caption pages and all 30 city record/text loads supplement
the representative gameplay checks. All 1,286 800K translation targets are
verified in the actual image.

Fourteen retained nonempty S2 tails outside native selector ranges, unused UI
entries and the floppy-only wording variant have explicit static/offline
coverage, not live-branch claims. See the frozen review's `readiness.json` and
`review-notes.json`. No 140K Korean port, floppy save interchange, emulator
save-state interchange or low-level host I/O fault injection is claimed.

The user also confirmed that the image works in their own testing on 2026-10-19.
Detailed captures are indexed in [runtime/README.md](runtime/README.md).
