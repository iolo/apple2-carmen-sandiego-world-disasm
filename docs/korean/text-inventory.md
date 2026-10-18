# Korean text inventory

Run `make korean-catalog` to extract, and `make korean-check` to verify the
catalog against the immutable inputs. IDs identify locations, not English
wording. The catalog is UTF-8; the original English and its encoding remain
separate from the approved Korean translation. Extraction never approves a translation.

The current catalog contains 1,468 entries and retains references to both
releases. The target 800K edition accounts for 1,467 entries: 1,286 translation
targets and 181 exclusions. One additional floppy-only S2 wording is retained
as `s2.city21.line24.disk2` ("need" versus the 800K edition's "needed").

| 800K source | Entries | Translation targets | Evidence and consumers |
| --- | ---: | ---: | --- |
| C UI | 130 | 130 | `C-ui-text.json`, `N_SELECT_UI_TEXT`, shared `n_ui_text_ids.inc` |
| C cities, suspects, ranks, weekdays/suffixes | 60 | 60 | `C-names.json`, N named selectors and centered-text path |
| C trait labels | 23 | 23 | `C-clues.json`, `N_CLUE_STRING_PTR_LO/HI` |
| C service pronouns | 2 | 2 | `C_PRONOUN_SHE/HE`, `C_APPEND_5000_PRONOUN` |
| C word dictionary | 128 | 0 | English codec components; full expanded S2 sentences are targets |
| I treasure names | 91 | 91 | Entire NUL-separated file, including final intentional empty string |
| K clue/response fragments | 41 | 41 | Entire NUL-separated file, `C_APPEND_5000_TEXT` |
| S2 | 960 | 920 | All 30 indexed records; 920 nonempty lines plus 40 structural empty fields |
| R intro/credits | 4 | 4 | `R_SELECT_INTRO_STRING`, `R_CENTER_INTRO_STRING`, independent R renderer |
| N save dialog and inline plural | 2 | 2 | `$86B1` dialog; scalar `s` in `N_REPORT_CASES_UNTIL_PROMOTION` |
| WORLD.SYSTEM and B messages | 12 | 0 | ROM COUT `$FDED` after switching to hardware TEXT MODE |
| Lettering in bitmaps | 14 | 13 | Visual inventory in `assets/korean/bitmap-text.json` |

The bitmap inventory covers the HGR splash, publisher/intro/title/office
images, the six Interpol trait labels and COMPUTER label, the JAIL sign,
and the clock's AM/PM glyphs. The splash publisher logo has a documented
brand-name exclusion; it is not classified as TEXT MODE. The other decoded
S/O/P views, 30 city landmarks, 30 C icons, eight R glyphs, five T frames,
and 26 U sprites were visually surveyed. Decorative architectural marks
remain picture artwork. Return/Escape keycap glyphs are input symbols.

Runtime-generated detective names, roster and hall-of-fame names are English
user input, not fixed translation strings. F/G/H contain persistent game data;
their names and case-state bytes must retain their existing formats. Clock
digits and case counts are decimal state values. Filesystem names, volume
signatures, and input comparisons are internal identifiers and remain English.

## Output and control paths

N has ordinary, centered, report/typewriter, and FF-terminated name output
paths. All reach `N_PREPARE_GLYPH_CHAR` or direct glyph-index rendering. C
selects and copies NUL-separated strings, including its auxiliary I/K lists.
R has separate selection, measurement, wrapping and glyph lookup routines.
Direct icon/sprite indexes are not character text and must keep their identity.

S2 entries retain both expanded English and lossless dictionary markup, plus
every dictionary token byte. `#`, `@`, `^` are protected pronouns only for
the S2/K consumers that substitute them; the literal `# Cases` UI label is
not a pronoun. `<CTRL:80>`, `<CTRL:81>`, `<CTRL:82>`, and `<CTRL:8D>` describe
original UI bytes. The [encoding rules](encoding.md) and native reader tests preserve these
controls and substitutions in the Korean image.

UI fragments are deliberately not deduplicated: names, deadlines, pronouns,
treasures and feedback are combined by N. Weekday stems and suffixes combine
with UI `day, `. Complete-sentence and dynamic-layout checks are recorded in `message-layouts.json`.

The ten suspect names and first five ranks also form the original 15-entry
name blacklist in `N_CHECK_RESERVED_NAME`. Their catalog `input_uses` requires
retaining the English comparison list separately when display names become
Korean. Translating the shared table alone would change game behavior. UI
Y/N prompts retain accepted bytes `$59/$4E` plus Return, and Control-D remains
`$04`; these are recorded as `input_tokens` rather than translated key bindings.

## Byte reconstruction and limits of the inventory

`catalog-roundtrip.json` records exact reconstructed text-byte counts and
SHA-256 identities for 26 original files. Original text is re-encoded from
ASCII, control markup, or S2 dictionary markup; raw hex is comparison evidence,
not the inverse encoder. Native image/font codecs verify bitmap sources.
Unclaimed executable and graphics bytes are preserved from immutable inputs.
This does not assert that English lettering can be regenerated from a bitmap
transcription alone.

The inline promotion suffix `s` is a separate, non-NUL `ascii-byte` entry.
Its approved Korean translation is empty because counters do not inflect; the
patch removes the complete append/cursor instruction span together. Other scalar outputs
are decimal state digits, quote/period/line formatting, echoed English input,
or a dash used as an animation stroke. Catalog `format_rules` records these
distinctions. In particular, the final-byte quote test must not mistake a
multibyte glyph's trail byte for an ASCII closing quote.

A scan of remaining NUL-terminated printable runs in C/N/R/Z found table,
instruction and pixel coincidences, not additional confirmed prose: C file
offset `$25BF`, N `$2679/$2A84/$2B96`, R `$0C04` and the pointer bytes before
the already cataloged intro text at `$0C5F`, and Z `$02DF`. WORLD.SYSTEM's
`/ram/`, volume signature and prefix, and B's `/carmen.world/s2` are internal
filesystem identifiers. R's retained disk-prompt fragment can index beyond
its four declared strings; no identified caller makes those bytes valid new
messages. Its unresolved reachability remains an analysis limit.

The catalog is a traced inventory of identified sources, not proof of every
runtime branch. All 30 cities and every 800K target pass static checks.
[Release checks](release-checks.md) record actual approved-text gameplay and
unplayed branches; [progress](progress.md) maps the completed K0–K6 work.
