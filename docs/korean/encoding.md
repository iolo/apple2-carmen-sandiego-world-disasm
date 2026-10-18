# Korean text encoding: carmen-ko-2byte-v1

The approved NFC catalog uses 710 Hangul syllables. Every cell was
extracted without clipping from the pinned GalmuriMono7 BDF into eight
seven-bit HGR scanlines. The font is 5,680 bytes. ASCII continues to use the
original D glyphs and their variable advances. Hangul advances eight pixels.
See `encoding-roundtrip.json` for hashes and the exact catalog version.

`make korean-fixtures` compiles and round-trips all 1,287 translations, including
bitmap captions. Its outputs in `build/korean/draft-fixtures/` are
compiler fixtures, separate from the approved image. This command does not
patch game media.

| Byte class | Meaning |
| --- | --- |
| `$20–$7E` | Literal ASCII, including spaces, quotes and pronoun markers |
| `$80–$8F` | Reserved native renderer controls; existing controls retain their values |
| `$90–$FE` followed by an allowed trail | One non-ASCII glyph ID |
| `$00`, `$FF` | Reserved terminators; never present inside a glyph |
| `$7F`, `$01–$1F` | Invalid encoded payload bytes |

Allowed trails are `$21–$7E` excluding `$22` (quote), `$23` (`#`), `$40`
(`@`) and `$5E` (`^`): 90 values in ascending order. IDs are assigned by
ascending Unicode scalar value. For ID `g`, the lead is `$90 + floor(g/90)`
and the trail is `trails[g mod 90]`. The theoretical encoding limit is 9,990
glyphs; it is not a RAM-capacity claim. Unassigned IDs, truncated pairs and
invalid trails fail decoding. No Unicode normalization occurs in the encoder;
non-NFC input fails instead. Draft editing performs explicit normalization.

Neither byte of a glyph can masquerade as a terminator, space, final quote,
or pronoun. NUL-based selectors and byte-copy routines can therefore retain
their delimiter semantics. Native C/N reader tests verify their page/cursor
rules. Raw backward scans for ASCII spaces cannot stop inside a glyph; the
no-space fallback breaks at a decoded glyph boundary.

Korean S2 data does not use the English dictionary. N's high-bit dictionary
branch is disabled for this edition. Pronouns are substituted before
rendering, with the original selection logic: `#` uses 자신, `@` uses 자신의,
and `^` uses 자신. The female object branch selects UI 105 rather than
the shared English possessive/object UI 104. Outer 그는/그녀는 remains distinct.
The source marker counts are protected by draft validation.

Both N and R decode a pair before applying the native `$8D` break test,
measuring a glyph or drawing it. Their direct glyph-index paths for icons and
T/U animation frames remain distinct from text decoding. The helper
consumes exactly one extra byte per pair, including across a page boundary,
and restores the native pointer/return contracts. A glyph immediately before
NUL does not consume the terminator.

Bitmap-caption newlines compile to `$8D` in compiler fixtures; the caption
engine places the final lines separately. N's inline English plural `s` is
an empty translation. Its complete nine-byte append/cursor instruction span
is replaced with NOPs, rather than writing a NUL glyph.

Synthetic fixtures rotate all 710 non-ASCII cells bijectively. They preserve
the exact used character set, every encoded length, eight-pixel advances,
ASCII, controls, pronoun markers and structural NULs. They contain no readable
Korean translation. The complete font can therefore be tested before
human approval. Full-font residency, the native installer/decoder and N/R text
hooks now have passing component evidence in `runtime/font-residency.json`,
`runtime/native-font.json` and `runtime/native-renderers.json`. The N/R rasters
match an independent pixel reference; the narrow typewriter's entire glyph
stream matches its layout, including the original leading `$80` marker rule.
`runtime/native-readers.json` verifies all assigned glyphs through the actual
N expansion and C auxiliary K readers. N's high-bit dictionary branch is
disabled; `#/@/^` remain substitutions, and female `^` selects UI 105. C and N
synchronize their output-page high bytes before/after pronoun copies. The
quote-aware sentence finisher handles a terminator at the start of a new page.
The original 15 English blacklist strings remain separately at LC `$D7BD`,
while Korean
display groups are repacked from `$DB11` with all consumers updated.

`runtime/synthetic-text.json` verifies disk boot, intro, registration,
investigation, travel, save and fresh-process restore with full-size synthetic
text. `runtime/native-clock.json` verifies the two full clock words. Complete
dynamic combinations, bitmap captions and actual approved-text execution pass;
see `message-layouts.json`, `runtime/approved/` and the [release summary](release-checks.md).
Detailed runtime captures are read from the indexed [evidence archive](runtime/README.md).
