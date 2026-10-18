"""Audit and archive the completed K0 MAME experiment from its real receipts.

No emulator run is inferred from file existence: captured state, exact loaded
module bytes, probe receipts, display pages and fresh-process save evidence
must all agree. This does not certify the future full Korean renderer.
"""

import argparse
from pathlib import Path
import shutil

from .common import BUILD, DOCS, ROOT, original_inputs, read_json, sha256, write_json


PLACEMENTS = [("C", "active-lc", 0xD200), ("C", "aux", 0x2000),
              ("D", "main", 0xB900), ("E", "main", 0xB200),
              ("I", "aux", 0x6000), ("K", "aux", 0x5000),
              ("J", "aux", 0x7000), ("P", "aux", 0x8000),
              ("T", "aux", 0x8500), ("U", "aux", 0x9400), ("O", "main", 0xA700)]


def audit(baseline, runtime):
    identities = original_inputs()
    save = read_json(DOCS / "runtime/mame-save-restore.json")
    if save["fresh_process_restore"] is None:
        raise ValueError("Fresh-process save/restore verification is incomplete")
    baseline_states = {name: read_json(baseline / f"{name}.json")
                       for name in ("city", "investigation", "after-navigation", "before-save")}
    first_city = baseline_states["city"]["case_state"]
    investigated = baseline_states["investigation"]["case_state"]
    traveled = baseline_states["after-navigation"]["case_state"]
    if (first_city[17] != investigated[17] or investigated[22] <= first_city[22]
            or first_city[17] == traveled[17]):
        raise ValueError("Baseline does not prove an investigation and a city change")
    if baseline_states["before-save"]["case_state"] != save["case_state"]:
        raise ValueError("Baseline checkpoint is not the independently audited saved case")
    manifest = read_json(BUILD / "probe/manifest.json")
    configuration = read_json(runtime / "session.json")
    if (configuration["machine"], configuration["main_kib"], configuration["auxiliary_kib"],
            configuration["aux_card"]) != ("apple2e", 64, 64, "ext80"):
        raise ValueError("MAME profile does not prove the requested 128K Apple //e")
    if configuration["image_sha256"] != save["saved_image_sha256"]:
        raise ValueError("Fresh process did not boot the independently verified saved disk")
    stages = {}
    for stage in ("intro-resident", "intro-after-probe", "game-entry", "restored-city"):
        receipt = read_json(runtime / f"{stage}.json")
        if not receipt["ramrd_restored"] or not all(receipt["mapping"][key]
                for key in ("ALTZP", "LCRAM", "LCBANK2")):
            raise ValueError(f"Unexpected mapping during {stage}")
        banks = {bank: (runtime / f"{stage}-{bank}.bin").read_bytes()
                 for bank in ("main", "aux", "active-lc")}
        if any(len(data) != (0x3000 if bank == "active-lc" else 0xBE00)
               for bank,data in banks.items()):
            raise ValueError(f"Truncated memory survey: {stage}")
        placements = PLACEMENTS.copy()
        if stage.startswith("intro"):
            placements += [("R", "main", 0x6000), ("S", "main", 0x7800)]
        elif stage == "game-entry":
            placements += [("N", "main", 0x6000)]
        observations = []
        for module, bank, address in placements:
            original = (ROOT / f"assets/po/{module}.bin").read_bytes()
            start = address - (0xD000 if bank == "active-lc" else 0x200)
            actual = banks[bank][start:start + len(original)]
            if actual != original:
                raise ValueError(f"{stage}: {module} does not match at {bank}:${address:04X}")
            observations.append({"file": module, "bank": bank, "address": address,
                                 "bytes": len(actual), "sha256": sha256(actual), "equals_original": True})
        stages[stage] = {"receipt": receipt, "observed_modules": observations}
    probes = {}
    for module, checkpoint in (("R", "intro-resident"), ("N", "game-entry")):
        receipt = read_json(runtime / f"probe-{module}.json")
        probe = manifest["probes"][module]
        if (receipt["probe"] != probe or not receipt["font_pointers_restored"]
                or receipt["stopped"]["PC"] != probe["done"] or receipt["cursor"]["row"] != 58):
            raise ValueError(f"Incomplete renderer probe: {module}")
        expected_cpu = stages[checkpoint]["receipt"]["cpu"]
        if any(receipt["cpu_restored"][name] != expected_cpu[name]
               for name in ("A", "X", "Y", "SP", "P", "PC")):
            raise ValueError(f"Probe did not restore its CPU registers: {module}")
        if sha256((ROOT / probe["path"]).read_bytes()) != probe["sha256"]:
            raise ValueError("Probe binary changed after measurement")
        page = (runtime / f"probe-{module}.hgr").read_bytes()
        if len(page) != 8192 or (runtime / f"probe-{module}.png").stat().st_size < 100:
            raise ValueError(f"Missing display capture: {module}")
        probes[module] = {"receipt": receipt, "hgr_sha256": sha256(page)}
    if probes["N"]["hgr_sha256"] != probes["R"]["hgr_sha256"]:
        raise ValueError("Original N/R renderers produced different synthetic output")
    if stages["restored-city"]["receipt"]["case_state"] != save["fresh_process_restore"]["case_state"]:
        raise ValueError("Archived restore checkpoint differs from the disk audit")
    return {"format": 1, "original_inputs": identities, "configuration": configuration,
            "baseline": {"first_city_index": first_city[17], "traveled_city_index": traveled[17],
                         "investigation_count_before": first_city[22], "investigation_count_after": investigated[22]},
            "stages": stages, "probes": probes, "save_restore": save,
            "runtime_source_sha256": sha256((ROOT / "tools/korean/runtime.lua").read_bytes()),
            "font_source": read_json(ROOT / "assets/korean/font/source.json"),
            "probe_allocation": {"bank": "main", "start": 0x9200, "bytes": 328,
                                 "available_candidate_bytes": 1536, "remaining_bytes": 1208},
            "limits": ["Two synthetic proxy glyphs, not the final multibyte encoding or full font",
                       "One rookie case; no full-case completion, promotion or every error branch",
                       "Full-draft RAM/disk capacity and final renderer lifecycle remain K2/K4 gates",
                       "Probe register changes require debugger instruction-boundary stops; ordinary pauses are insufficient"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--runtime", type=Path, required=True)
    args = parser.parse_args()
    report = audit(args.baseline, args.runtime)
    destination = DOCS / "runtime/mame"
    destination.mkdir(parents=True, exist_ok=True)
    for name in ("sign-in", "city", "investigation", "after-navigation", "before-save", "after-save"):
        for suffix in (".json", ".png"):
            shutil.copyfile(args.baseline / (name + suffix), destination / ("baseline-" + name + suffix))
    for stage in report["stages"]:
        shutil.copyfile(args.runtime / f"{stage}.json", destination / f"{stage}.json")
        for bank in ("main", "aux", "active-lc"):
            name = f"{stage}-{bank}.bin"
            shutil.copyfile(args.runtime / name, destination / name)
    shutil.copyfile(args.runtime / "restored-city.png", destination / "restored-city.png")
    for module in ("N", "R"):
        for suffix in (".json", ".png", ".hgr"):
            name = "probe-" + module + suffix
            shutil.copyfile(args.runtime / name, destination / name)
    write_json(DOCS / "runtime/mame-k0.json", report)
    print("K0 runtime audit: 128K Apple //e; exact resident assets and overlay entries; matching N/R probes; fresh-boot restore.")


if __name__ == "__main__":
    main()
