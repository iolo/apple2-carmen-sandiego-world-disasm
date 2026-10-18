"""Compile synthetic text, or real translations after explicit human approval.

Synthetic mode replaces non-ASCII characters with a bijective permutation,
preserving the complete charset, native metrics, byte lengths and controls.
English input guards and all original picture streams remain byte-identical.
"""

import re
import sys

from .catalog import CATALOG
from .clock import compile_clock, patch_source as patch_clock_source
from .captions import build as build_captions
from .common import BUILD, ROOT, original_inputs, read_json, sha256, write_json
from .draft import audit
from .encoding import GameEncoding
from .library import assemble
from .renderers import build as build_renderers, word

sys.path.insert(0, str(ROOT / "tools"))
from extract_assets import s2_index
from reconstruct import write_c_embedded_sources, write_n_dialog_source


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError(f"Source contract is not unique: {old[:100]!r}")
    return source.replace(old, new)


def byte_source(data):
    return "".join("        .byte " + ",".join(f"${b:02X}" for b in data[i:i+16]) + "\n"
                   for i in range(0, len(data), 16))


def assert_bound(name, required, available):
    if required > available:
        raise ValueError(f"STOP: {name} requires {required} bytes; {available} available; "
                         f"shortfall {required-available}. User decision required before an alternative.")


def build(*, approved=False):
    receipt = None
    if approved:
        from .approval import require
        receipt = require()  # Before creating/writing any production output.
    identity = original_inputs()
    catalog = read_json(CATALOG)
    coverage = audit(catalog, complete=True)
    encoding = GameEncoding.from_catalog(catalog)
    entries = {e["id"]: e for e in catalog["entries"]
               if any(r["variant"] == "po" for r in e["references"])}
    mode = "approved" if approved else "synthetic"
    directory = BUILD / mode / "text"
    directory.mkdir(parents=True, exist_ok=True)
    renderer = build_renderers()
    covered = set()

    def payload(identifier):
        covered.add(identifier)
        return encoding.entry(entries[identifier], synthetic=not approved)

    def group(prefix):
        return b"".join(payload(identifier) for identifier in sorted(entries)
                        if identifier.startswith(prefix))

    outputs = {}

    def output(name, data, **details):
        path = directory / f"{name}.bin"
        path.write_bytes(data)
        outputs[name] = {"path": str(path.relative_to(ROOT)), "bytes": len(data),
                         "sha256": sha256(data), **details}

    for name in ("I", "K"):
        data = group(name.lower() + ".")
        assert_bound(name + " auxiliary reservation", len(data), 4096)
        output(name, data, capacity=4096)

    ddata, clock = compile_clock(encoding, entries, synthetic=not approved)
    covered.update(("bitmap.d.am", "bitmap.d.pm"))
    output("D", ddata, clock=clock, capacity=1536)

    # Rebuild the 24-bit index and each 16-bit text/image boundary. Copy each
    # compressed picture from the verified original without transcoding it.
    original_s2 = (ROOT / "assets/po/S2.bin").read_bytes()
    offsets, records, cities = [192], [], []
    for record in s2_index(original_s2):
        lines = {}
        for entry in entries.values():
            for ref in entry["references"]:
                if ref["variant"] == "po" and ref["file"] == "S2" and ref.get("record") == record["number"]:
                    lines[ref["string_index"]] = entry["id"]
        if sorted(lines) != list(range(len(lines))):
            raise ValueError("S2 string indices are not contiguous")
        text = b"".join(payload(lines[i]) for i in range(len(lines)))
        assert_bound("S2 stored text before O", len(text), 1792)
        if not text.endswith(b"\0\0"):
            raise ValueError("S2 structural empty strings lost")
        old = original_s2[record["start"]:record["end"]]
        picture = old[int.from_bytes(old[:2], "little"):]
        boundary = 2 + len(text)
        assert_bound("S2 16-bit boundary", boundary, 65535)
        data = word(boundary) + text + picture
        records.append(data)
        offsets.append(offsets[-1] + len(data))
        cities.append({"city": record["number"], "strings": len(lines), "text_bytes": len(text),
                       "boundary": boundary, "picture_bytes": len(picture), "picture_sha256": sha256(picture)})
    assert_bound("S2 24-bit offset", offsets[-1], 0xFFFFFF)
    s2 = b"".join(v.to_bytes(3, "little") for v in offsets).ljust(192, b"\0") + b"".join(records)
    output("S2", s2, cities=cities)

    cdir = directory / "C-source"
    cdir.mkdir(exist_ok=True)
    write_c_embedded_sources("po", cdir)
    source = (ROOT / "src/disk1/C.s").read_text()
    source = replace_once(source, '.setcpu "6502"', '.setcpu "6502"\nK_C_BASE:')
    source = replace_once(source, "        sta     $A000,y\n        cmp     #$00", "        sta     ($DA),y\n        cmp     #$00")
    source = replace_once(source, "        iny\nC_APPEND_5000_NEXT_BYTE:",
                          "        iny\n        bne C_APPEND_5000_NEXT_BYTE\n        inc $DB\nC_APPEND_5000_NEXT_BYTE:")
    source = replace_once(source, "C_APPEND_5000_DONE: sta $C002", "C_APPEND_5000_DONE: sty $AC\n        sta $C002")
    for sex in ("SHE", "HE"):
        source = replace_once(source, f'C_PRONOUN_{sex}: ' + (' .asciiz "he"' if sex == "HE" else '.asciiz "she"'),
                              f"C_PRONOUN_{sex}:\n" + byte_source(payload(f"c.service.{sex.lower()}")))
    source = replace_once(source, "        .res 37, $00", "        .res 512 - (* - K_C_BASE), $00")

    # Preserve the same fifteen original English comparisons, independently
    # of all translated display names, in the former dictionary reservation.
    original_c = (ROOT / "assets/po/C.bin").read_bytes()
    start = 0xDC0F - 0xD200
    end = start
    for _ in range(15):
        end = original_c.index(0, end) + 1
    guard = original_c[start:end]
    dictionary = "C_WORD_DICTIONARY:\nK_RESERVED_ENGLISH_NAMES:\n" + byte_source(guard)
    dictionary += "        .res $D900-$D7BD-(*-C_WORD_DICTIONARY), $00\n"
    for name, label, size, pad in (("trail-map", "K_TRAIL_MAP", 256, 0),
                                   ("lead-lo", "K_LEAD_OFFSET_LO", 111, 1),
                                   ("lead-hi", "K_LEAD_OFFSET_HI", 111, 0)):
        data = (BUILD / f"library/{name}.bin").read_bytes()
        if len(data) != size:
            raise ValueError("Lookup table size changed")
        dictionary += label + ":\n" + byte_source(data) + (f"        .res {pad}, $00\n" if pad else "")
    dictionary += "        .res $DB11-$D7BD-(*-C_WORD_DICTIONARY), $00\n"
    groups = (("cities", "C_CITY_NAMES"), ("suspects", "C_SUSPECT_NAMES"),
              ("detective_ranks", "C_DETECTIVE_RANKS"), ("weekdays", "C_WEEKDAYS"),
              ("weekday_suffixes", "C_WEEKDAY_SUFFIXES"))
    name_groups = [(label, group(f"c.{name}.")) for name, label in groups]
    assert_bound("C names before fixed icon pointers", sum(len(data) for _, data in name_groups), 495)
    names = "".join(label + ":\n" + byte_source(data) for label, data in name_groups)
    names += "        .res $DD00-$DB11-(*-C_CITY_NAMES), $00\n"
    begin, finish = source.index("C_WORD_DICTIONARY:"), source.index("; Thirty split pointers")
    source = source[:begin] + dictionary + names + source[finish:]
    traits = (("sex", "C_SEX_LABELS"), ("hobbies", "C_HOBBY_LABELS"), ("hair", "C_HAIR_LABELS"),
              ("features", "C_FEATURE_LABELS"), ("vehicles", "C_VEHICLE_LABELS"), ("food", "C_FOOD_LABELS"))
    begin, finish = source.index("C_SEX_LABELS:"), source.index('; Interface strings occupy')
    clue_groups = [(label, group(f"c.clue.{name}.")) for name, label in traits]
    assert_bound("C trait labels before UI", sum(len(data) for _, data in clue_groups), 0xE000-0xDD7C)
    clue_source = "".join(label + ":\n" + byte_source(data) for label, data in clue_groups)
    clue_source += "        .res $E000-$DD7C-(*-C_SEX_LABELS), $00\n"
    source = source[:begin] + clue_source + source[finish:]
    ui = group("c.ui.")
    assert_bound("C UI before icons", len(ui), 3072)
    (cdir / "c_ui_text.inc").write_text(byte_source(ui) + f"        .res {3072-len(ui)}, $00\n")
    (cdir / "C.s").write_text(source)
    cdata, symbols = assemble(cdir / "C.s", cdir, "C", 0xD200, len(original_c))
    if len(cdata) != len(original_c):
        raise ValueError("C total length changed")
    for low, high in ((0xD400, 0xD7BD), (0xDD00, 0xDD7C), (0xEC00, 0xF979)):
        if cdata[low-0xD200:high-0xD200] != original_c[low-0xD200:high-0xD200]:
            raise ValueError("C fixed tables or original icons changed")
    for label, expected in (("C_X_BYTE_OFFSET", 0xD400), ("C_WORD_DICTIONARY", 0xD7BD),
                            ("C_CITY_NAMES", 0xDB11), ("C_ICON_PTR_LO", 0xDD00),
                            ("C_SEX_LABELS", 0xDD7C)):
        if symbols[label] != expected:
            raise ValueError(f"C fixed boundary moved: {label}")
    output("C", cdata, symbols=symbols, english_blacklist_hex=guard.hex(),
           english_blacklist_address=symbols["K_RESERVED_ENGLISH_NAMES"])

    # Generate only address-preserving operand/call changes inside original N.
    # Appended helpers/text follow the already-probed renderer extension.
    ndir = directory / "N-source"
    ndir.mkdir(exist_ok=True)
    native = read_json(BUILD / "maps/N-symbols.json")
    base = (ROOT / renderer["modules"]["N"]["path"]).read_bytes()
    (ndir / "text-config.inc").write_text(f"N_APPEND_UI_TEXT = ${native['N_APPEND_UI_TEXT']:04X}\n")
    hooks, hook_symbols = assemble(ROOT / "src/korean/text_hooks.s", ndir, "text-hooks", 0x6000+len(base), 0x9200-0x6000-len(base))
    save = payload("n.save_dialog")
    save_address = 0x6000 + len(base) + len(hooks)
    nsource = (ROOT / "src/po/N.s").read_text()
    nsource = patch_clock_source(nsource, replace_once)
    for _, label in groups:
        nsource, count = re.subn(rf"^{label} := \$[0-9A-F]+$", f"{label} := ${symbols[label]:04X}", nsource, flags=re.M)
        if count != 1:
            raise ValueError("N display-name constant not found")
    nsource = '.include "integration-config.inc"\n' + nsource
    (ndir / "integration-config.inc").write_text("".join(f"{k} = ${v:04X}\n" for k, v in hook_symbols.items() if k.startswith("K_")) +
                                                f"K_RESERVED_ENGLISH_NAMES = ${symbols['K_RESERVED_ENGLISH_NAMES']:04X}\nK_SAVE_DIALOG = ${save_address:04X}\n")
    a, b = nsource.index("N_CHECK_RESERVED_NAME:"), nsource.index("N_REJECT_RESERVED_NAME:")
    nsource = nsource[:a] + nsource[a:b].replace("#<C_SUSPECT_NAMES", "#<K_RESERVED_ENGLISH_NAMES").replace("#>C_SUSPECT_NAMES", "#>K_RESERVED_ENGLISH_NAMES") + nsource[b:]
    nsource = replace_once(nsource, "        bmi     N_EXPAND_DICTIONARY_TOKEN", "        nop\n        nop")
    nsource = replace_once(nsource, "        lda     #$A0\n        sta     $DD\nN_READ_NEXT_TEXT_TOKEN:",
                           "        lda     $DB\n        sta     $DD\nN_READ_NEXT_TEXT_TOKEN:")
    nsource = replace_once(nsource, "N_APPEND_CHOSEN_PRONOUN:  jsr     N_APPEND_UI_TEXT", "N_APPEND_CHOSEN_PRONOUN:  jsr K_APPEND_CHOSEN_PRONOUN")
    nsource = replace_once(nsource, "        jmp     N_TEXT_EXPANSION_DONE", "        jmp K_TEXT_EXPANSION_DONE")
    a, b = nsource.index("N_APPEND_OBJECT_PRONOUN:"), nsource.index("N_USE_HIM_PRONOUN:")
    nsource = nsource[:a] + nsource[a:b].replace("#N_UI_HER_WORD", "#N_UI_HIM_WORD") + nsource[b:]
    plural = "        ldy     $AC\n        lda     #$73\n        sta     $A000,y\n        inc     $AC\n"
    nsource = replace_once(nsource, plural, "        .res 9, $EA\n")
    for label in ("N_CLUE_STRING_PTR_LO", "N_CLUE_STRING_PTR_HI"):
        values = [symbols[name] & 255 if label.endswith("LO") else symbols[name] >> 8 for _, name in traits]
        nsource, count = re.subn(rf"^{label}:.*$", label + ": .byte " + ",".join(f"${v:02X}" for v in values), nsource, flags=re.M)
        if count != 1:
            raise ValueError("N clue pointer table not found")
    nsource = nsource.replace("#<N_SAVE_DIALOG_TEXT", "#<K_SAVE_DIALOG").replace("#>N_SAVE_DIALOG_TEXT", "#>K_SAVE_DIALOG")
    # The original entry is replaced with JMP + padding, keeping every later
    # symbol (including public overlay call addresses) at its original address.
    a, b = nsource.index("N_END_TEXT_SENTENCE:"), nsource.index("N_APPEND_SUSPECT_SUBJECT_PRONOUN:")
    extent = native["N_APPEND_SUSPECT_SUBJECT_PRONOUN"] - native["N_END_TEXT_SENTENCE"]
    nsource = nsource[:a] + f"N_END_TEXT_SENTENCE: jmp K_END_TEXT_SENTENCE\n        .res {extent-3}, $EA\n\n" + nsource[b:]
    for include in re.findall(r'"\.\./shared/([^"]+)"', nsource):
        (ndir / include).write_bytes((ROOT / "src/shared" / include).read_bytes())
        nsource = nsource.replace(f'"../shared/{include}"', f'"{include}"')
    write_n_dialog_source(ndir / "n_dialog.inc")
    (ndir / "N.s").write_text(nsource)
    derived, derived_symbols = assemble(ndir / "N.s", ndir, "N", 0x6000, 0x2EE0)
    original_n = (ROOT / "assets/po/N.bin").read_bytes()
    if len(derived) != len(original_n):
        raise ValueError("Derived N changes original extent")
    # No original code/data label may move. Constants are allowed to change.
    for label, value in native.items():
        if 0x6000 <= value < 0x8EE0 and label in derived_symbols and derived_symbols[label] != value:
            raise ValueError(f"N original label moved: {label}")
    patches = []
    patched = bytearray(base)
    for index, (old, new) in enumerate(zip(original_n, derived)):
        if old == new:
            continue
        if patched[index] != old:
            raise ValueError("Reader operand patch overlaps a renderer patch")
        patched[index] = new
        patches.append({"address": 0x6000+index, "old": old, "new": new})
    patched.extend(hooks + save)
    assert_bound("N before resident library", len(patched), 0x9200-0x6000)
    covered.add("n.plural_suffix")
    output("N", bytes(patched), hooks=hook_symbols, save_dialog_address=save_address, operand_patches=patches)

    rbase = bytearray((ROOT / renderer["modules"]["R"]["path"]).read_bytes())
    rnative = read_json(BUILD / "maps/R-symbols.json")
    address = 0x6000 + len(rbase)
    site = rnative["R_SELECT_INTRO_STRING"] + 1 - 0x6000
    expected = b"\xA2" + bytes((rnative["R_CASE_ANNOUNCEMENT"] & 255,)) + b"\xA0" + bytes((rnative["R_CASE_ANNOUNCEMENT"] >> 8,))
    if rbase[site:site+4] != expected:
        raise ValueError("R intro selector contract differs")
    rbase[site:site+4] = b"\xA2" + bytes((address & 255,)) + b"\xA0" + bytes((address >> 8,))
    rbase.extend(group("r.intro."))
    assert_bound("R before S overlay", len(rbase), 0x7800-0x6000)
    output("R", bytes(rbase), intro_address=address)
    captions = build_captions(bytes(patched), bytes(rbase), encoding, entries, synthetic=not approved)
    for module in ("N","R"):
        details = {key:value for key,value in outputs[module].items() if key not in ("path","bytes","sha256")}
        details["captions"] = captions[module+"_metadata"]
        output(module, captions[module], **details)
    output("KL", captions["KL"], base_library_bytes=captions["manifest"]["base_library_bytes"],
           caption_engine=captions["manifest"])
    covered.update(captions["manifest"]["covered_entries"])
    if receipt is not None and receipt["catalog_sha256"] != coverage["catalog_sha256"]:
        raise ValueError("The compiled catalog differs from the human-approved version")
    report = {"format": 1, "mode": mode, "catalog_sha256": coverage["catalog_sha256"],
              "original_inputs": identity, "files": outputs, "covered_entries": sorted(covered),
              "remaining_display_entries": sorted(e["id"] for e in entries.values() if e["translatable"] and e["id"] not in covered),
              "renderer_library_sha256": renderer["library_sha256"],
              "captions": captions["manifest"],
              "status": ("full-size synthetic text and caption assets; disk/runtime evidence is recorded separately" if not approved else
                         "human-approved text and caption assets; actual-translation runtime verification required")}
    write_json(directory / "manifest.json", report)
    print(f"Compiled {mode} C/D/I/K/S2/N/R; English input guards and original picture streams preserved")
    return report


if __name__ == "__main__":
    build()
