"""Launch an owned 128K Apple //e with writable media and a local Lua mailbox.

Uses the a2-mame skill's control.lua API. Local ROMs are prerequisites, never
downloaded. CFFA's 6502 firmware permits the unenhanced apple2e model.
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess

from .common import BUILD, ROOT, sha256, write_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", required=True, help="new directory below build/korean")
    parser.add_argument("--rompath", type=Path, default=Path("/home/iolo/workspace/retro/a2x/mame/roms"))
    parser.add_argument("--cffa-rom", type=Path, default=Path("/home/iolo/workspace/retro/a2x/disks/roms/cffa20ee02.bin"))
    parser.add_argument("--image", type=Path, default=ROOT / "build/carmen-world.po")
    parser.add_argument("--script", type=Path)
    parser.add_argument("--console", action="store_true", help="opt into the old interactive stdin console")
    args = parser.parse_args()
    executable = shutil.which("mame")
    if not executable:
        parser.error("MAME is required")
    if not args.cffa_rom.is_file() or not args.rompath.is_dir() or not args.image.is_file():
        parser.error("local Apple //e ROMs, CFFA 6502 ROM and built disk are required")
    if Path(args.session).name != args.session:
        parser.error("session must be a single directory name")
    work = BUILD / args.session
    work.mkdir(parents=True, exist_ok=False)
    romdir = work / "roms/a2cffa02"
    romdir.mkdir(parents=True)
    shutil.copyfile(args.cffa_rom, romdir / "cffa20ee02.bin")
    rompath = f"{work / 'roms'};{args.rompath.resolve()}"
    for machine in ("apple2e", "a2cffa02"):
        subprocess.run([executable, "-verifyroms", machine, "-rompath", rompath], check=True)
    media = work / "carmen-world.hdv"
    shutil.copyfile(args.image, media)
    (work / "mailbox").mkdir()
    command = [executable, "apple2e", "-noreadconfig", "-rompath", rompath,
               "-aux", "ext80", "-ramsize", "64K", "-sl7", "cffa202", "-hard1", str(media),
               "-pluginspath", f"{ROOT / 'tools/korean/mame_plugins'};/usr/share/games/mame/plugins",
               "-plugin", "carmen_mailbox",
               "-skip_gameinfo", "-window", "-nomouse", "-nothrottle", "-homepath", str(work),
               "-video", "none", "-sound", "none", "-debug", "-debugger", "qt"]
    if args.console:
        command += ["-console"]
    for option in ("cfg_directory", "nvram_directory", "snapshot_directory", "state_directory", "diff_directory"):
        directory = work / option
        directory.mkdir()
        command += ["-" + option, str(directory)]
    if args.script:
        command += ["-autoboot_script", str(args.script.resolve()), "-autoboot_delay", "0"]
    write_json(work / "session.json", {"command": command, "machine": "apple2e", "pid": os.getpid(),
        "main_kib": 64, "auxiliary_kib": 64, "aux_card": "ext80", "controller": "cffa202",
        "image_source": str(args.image), "image_sha256": sha256(args.image.read_bytes()),
        "cffa_sha256": sha256(args.cffa_rom.read_bytes()),
        "note": "Disposable media; saves must not touch original images or English build output"})
    print(f"Session: {work}", flush=True)
    print(f"Lua: python3 -m tools.korean.mame_rpc --session {args.session} --call status", flush=True)
    environment = os.environ.copy()
    environment.update(SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy", QT_QPA_PLATFORM="offscreen")
    environment.update(CARMEN_MAME_ROOT=str(ROOT), CARMEN_MAME_WORK=str(work))
    if not args.console:
        # Keep diagnostics readable without polling a terminal/stdin tool.
        log = os.open(work / "mame.log", os.O_CREAT | os.O_WRONLY | os.O_EXCL, 0o600)
        os.dup2(log, 1)
        os.dup2(log, 2)
        os.close(log)
    os.execve(executable, command, environment)


if __name__ == "__main__":
    main()
