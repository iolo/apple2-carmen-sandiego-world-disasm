# Korean patch completion and evidence map

K0–K6 are complete for the approved **128K Apple //e / 800K ProDOS** edition.
The user approved all 1,287 translation targets; 1,286 belong to this image and
one is a preserved floppy-only variant. The user also confirmed successful
independent testing on 2026-10-19.

| Stage | Evidence |
| --- | --- |
| K0: English baseline and actual capacity | `english-baseline.json`, `original-capacity.json`, [memory layout](memory-layout.md), `runtime/mame-k0.json` |
| K1: Complete traced text inventory | [Text inventory](text-inventory.md), `catalog-roundtrip.json`; 1,468 entries, protected tokens and English TEXT MODE exclusions |
| K2: Translation, font and layout feasibility | `draft-status.json`, `draft-capacity.json`, `message-layouts.json`, `encoding-roundtrip.json`, `review-readiness.json`; 710 Hangul cells, all city/trait selectors, 1,697 dynamic combinations and 1,023 warrant subsets |
| K3: Human review and approval | [Review bundle](review/index.html), [receipt](../../assets/korean/approval.json), `approval-evidence.json` |
| K4: Native encoding, font and both renderers | `runtime/native-font.json`, `runtime/native-renderers.json` and the six approved component/lifecycle reports in `runtime/approved/` |
| K5: Approved image and reproducible build | `approved-build.json`, `approved-image-check.json`, `clean-build.json`; all 27 files and metadata checked, repeat and fresh-source builds identical |
| K6: Gameplay, saves, visual checks and regressions | [Release checks](release-checks.md), `runtime/approved/gameplay.json`, `save-compatibility.json`, `disk-errors.json`, `visual.json`, `english-baseline.json` |

The [requirement audit](plan-requirements.json) maps each of the plan's 29
requirements to evidence. The [aggregate audit](release-check.json) pins
report/artifact hashes and 128K machine profiles, compares English/Korean case
outcomes, and checks source/font/image/approval identity.

## Recorded result

The final text uses **카르멘 샌디에고**, retains **프리아모스의 가면**, and uses
**몬테수마의 복수(?)의 비밀 치료법**. The original English sources and images
remain unchanged. The approved image has 1,179 free ProDOS blocks; no extra
RAM, game compression, asset streaming or additional media was introduced.

Native tests cover all assigned glyphs through C/N readers, both pronoun cases,
31 clock cases, captions on both HGR pages, message extrema and all 60 city
record/text loads. Paired gameplay covers six trait inputs, warrants, arrests,
wrong/no warrant, promotion, timeout and Carmen retirement. Same-build saves,
English↔Korean cold restores and recoverable disk errors pass.

Every random route, clue choice, full-roster/hall replacement and name-editing
branch was not played. Retained unselected S2 tails and unused/floppy-only UI
have explicit static/offline coverage. [Release checks](release-checks.md)
describe those limits; no 140K Korean port or floppy save interchange is claimed.

## Reproduction

Use [runtime-workflow.md](runtime-workflow.md) for commands. Detailed captures
are preserved in the indexed [runtime archive](runtime/README.md), while the
approved review remains directly browsable and [older drafts](review/README.md)
are archived. Repeated test runs can write new loose captures without unpacking
the historical archive.
