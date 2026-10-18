# Runtime verification records

These reports document the tests already run. To understand the patch, start
with the [release summary](../release-checks.md), [screenshots](../screenshots/README.md)
and [technical guides](../README.md). Reproduction commands are in the
[runtime workflow](../runtime-workflow.md).

| Reports | Purpose |
| --- | --- |
| `approved/synthetic-text.json` | Approved-text boot, English registration/input, investigation, computer, travel, save and cold restore; the filename is shared with the synthetic suite, while `mode` records `approved` |
| `approved/gameplay.json` | Paired English/Korean warrants, arrests, failures, promotion, timeout and retirement |
| `approved/save-compatibility.json` | Cold save transfers in both directions |
| `approved/disk-errors.json`, `approved/visual.json` | Native error recovery and the longest city description |
| `approved/native-*.json` | Reader, clock, caption, message and city-load component checks |
| Top-level `*.json` | English baseline, initial RAM/font investigations and synthetic feasibility preceding approval |

## Detailed captures

`artifacts.tar.xz` contains the exact screenshots, HGR pages, memory dumps,
glyph traces, saved test payloads and session profiles referenced by the
reports, plus earlier development runs. `artifacts.json` indexes every member
by its original path, byte count and SHA-256. These captures are useful when
diagnosing a regression; browsing every run is unnecessary for ordinary patch
work.

The release and review auditors read the archive directly. Temporary MAME
session folders under `build/` are not required to check the retained evidence.
A newly reproduced loose capture takes precedence over its archived version.

```sh
python3 -m tools.korean.evidence check
python3 -m tools.korean.evidence extract --archive runtime --output build/runtime-evidence
```

Extraction requires a new output directory and restores the original paths
beneath it. It does not alter the image, approval record or player saves.
