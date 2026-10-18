"""Paired English/Korean gameplay and cold-boot save interoperability checks.

Fixtures are native-generated routes stored in the unchanged F/G/H format.
Tests enter branches through menus; no gameplay instruction is patched.
"""

import argparse
import shutil
import subprocess
import sys

from . import test_mode
from .common import BUILD, DOCS, ROOT, read_json, sha256, write_json
from .font_lifecycle import Session
from .synthetic_test import SyntheticSession, launch as start
from .verify_save import extract
from .evidence import read as read_evidence

sys.path.insert(0, str(ROOT / 'tools'))
from reconstruct import make_fimg, run


def replace_files(base, target, payloads):
    """Edit only unmounted, disposable images, keeping source metadata."""
    if target.exists() or target.resolve() in (ROOT / 'carmen-world.po', BUILD / 'approved/carmen-world-ko.po'):
        raise ValueError('New disposable image required')
    shutil.copyfile(base, target)
    for name, data in payloads.items():
        metadata = read_json(ROOT / 'reconstruction/manifest.json')['images']['po']['files'][name]
        run('a2kit', 'delete', '-d', str(target), '-f', name)
        run('a2kit', 'put', '-d', str(target), '-f', name, '-t', 'any', input_bytes=make_fimg(name, metadata, data))
        assert extract(target, name) == data
    return target


class GameSession(SyntheticSession):
    def __init__(self, name, language):
        super().__init__(name, 'approved')
        self.language = language
        self.events = []

    def drain_menu_input(self):
        """Let MAME finish releasing a posted Return before the next action.

        Read taps suppress only stale host input during this idle interval;
        game code keeps polling normally. No instruction or state is patched.
        """
        import time
        self.clear()
        self.call('korean_fast_text', False)
        self.lua("assert(not k0.input_drain);local s=manager.machine.devices[':maincpu'].spaces.program;"
                 "k0.input_drain=s:install_read_tap(0xC000,0xC062,'drain-posted-key',function(a,d,m) "
                 "if a~=0xC000 and a~=0xC061 and a~=0xC062 then return end;"
                 "if not manager.machine:side_effects_disabled() then s:read_u8(0xC010);return 0 end end);return true")
        before = self.call('status')['time']; self.call('go')
        deadline = time.monotonic() + 5
        while True:
            ready = self.lua('return {time=manager.machine.time:as_double(),empty=manager.machine.natkeyboard.empty,posting=manager.machine.natkeyboard.is_posting}')
            if ready['time'] > before+.3 and ready['empty'] and not ready['posting']:
                break
            if time.monotonic() > deadline:
                raise TimeoutError('Posted keyboard input did not finish')
        self.current = self.bp('N_WAIT_MENU_SELECTION'); self.stopped('N_WAIT_MENU_SELECTION')
        self.lua("k0.input_drain:remove();k0.input_drain=nil;manager.machine.devices[':maincpu'].spaces.program:read_u8(0xC010);return true")

    def row(self, direction):
        self.drain_menu_input()
        before = self.call('read', 0x6C, 4)['bytes']
        super().row(direction)
        expected = (before[0]+direction-before[2]) % (before[3]-before[2]+1) + before[2]
        if self.call('read',0x6C,1)['bytes'][0] != expected:
            raise ValueError('Arrow did not change exactly one menu row')

    def enter_menu(self, entry):
        self.drain_menu_input()
        return super().enter_menu(entry)

    def checkpoint(self, name):
        name = self.language + '-' + name.replace('font-', '').replace('synthetic-', '')
        result = Session.checkpoint(self, name)
        self.events.append({'name': name, 'case_state': result['case_state'],
                            'rank_solved': self.call('read', 0x5B, 2)['bytes']})
        # Exact native display bytes avoid any paused-video frame lag.
        self.lua("local s=manager.machine.devices[':maincpu'].spaces.program; "
                 "local p=(s:read_u8(0xC01C)&128)~=0 and 0x4000 or 0x2000; "
                 "local f=assert(io.open(k0.work..'/" + name + ".hgr','wb')); "
                 "for a=p,p+8191 do f:write(string.char(s:read_u8(a))) end;f:close();return p")
        from .caption_test import preview
        preview((self.directory / (name + '.hgr')).read_bytes(), self.directory / (name + '-native.png'))
        return result

    def guard(self, name, module=None):
        result = self.checkpoint(name)
        if self.language == 'korean':
            self.call('korean_synthetic_check', 'game-' + name.replace('font-', '').replace('synthetic-', ''), *([module] if module else []))
        return result

    def boot_game(self, detective, *, prompt=False, expected=None):
        point = self.bp(0x601C); self.call('go'); self.stopped(0x601C); self.clear(point)
        if self.language == 'korean':
            test_mode.bootstrap(self)
            self.guard('intro', 'R')
        point = self.bp(0x6000); self.call('go'); self.call('keys', '\r'); self.stopped(0x6000); self.clear(point)
        self.guard('overlay', 'N')
        point = self.bp('N_READ_NAME_KEY'); self.call('go'); self.stopped('N_READ_NAME_KEY'); self.clear(point)
        self.call('korean_fast_text', True)
        if prompt:
            point = self.bp('N_READ_YES_NO_RESPONSE')
            self.call('go'); self.call('keys', detective + '\r'); self.stopped('N_READ_YES_NO_RESPONSE'); self.clear(point)
            self.guard('resume-or-create')
        self.current = self.bp('N_WAIT_CITY_INPUT'); self.call('go')
        self.call('keys', 'Y\r' if prompt else detective + '\r')
        self.stopped('N_WAIT_CITY_INPUT'); self.call('korean_fast_text', False)
        result = self.guard('city')
        if expected is not None:
            expected = list(expected); expected[26] = 2; expected[22] = 0
            if result['case_state'] != expected:
                raise ValueError('Cold restore changed case fields beyond native menu/count resets')
        return result['case_state']

    def advance_to(self, label, key='\r', name='report'):
        """Run native code, acknowledging actual continuation prompts."""
        self.clear()
        target = self.bp(label)
        wait = self.bp('N_POLL_KEY_OR_BUTTON')
        keyboard_wait = self.bp('N_POLL_GAME_KEYBOARD')
        self.call('korean_fast_text', key != '\x1b')
        if key is not None:
            self.lua('manager.machine.natkeyboard:post(string.char(' + ','.join(str(b) for b in key.encode('ascii')) + '));return a2.go()')
        else:
            self.call('go')
        for index in range(24):
            # Both breakpoints are instruction boundaries; inspect which fired.
            import time
            deadline = time.monotonic() + 30
            while self.call('status')['debugger'] != 'stop':
                if time.monotonic() > deadline:
                    raise TimeoutError('Gameplay did not reach ' + label)
                time.sleep(.05)
            pc = self.call('registers')['PC']
            if pc == self.symbols[label]:
                self.clear(wait); self.clear(keyboard_wait); self.current = target
                self.call('korean_fast_text', False)
                return self.guard(name)
            if pc not in (self.symbols['N_POLL_KEY_OR_BUTTON'],self.symbols['N_POLL_GAME_KEYBOARD']):
                raise ValueError('Unexpected gameplay stop')
            self.guard(name + '-continue-' + str(index))
            # Remove polling stops while the posted key is being delivered.
            # Queue and resume atomically so a fast re-stop cannot race keys().
            self.clear(wait); self.clear(keyboard_wait)
            self.lua('manager.machine.natkeyboard:post(string.char(13));return a2.go()')
            wait=self.bp('N_POLL_KEY_OR_BUTTON');keyboard_wait=self.bp('N_POLL_GAME_KEYBOARD')
        raise ValueError('Too many continuation prompts')

    def visit(self, place, endpoint='N_WAIT_CITY_INPUT', name='investigation'):
        self.enter_menu('N_SHOW_INVESTIGATION_MENU')
        for _ in range(place):
            self.row(1)
        return self.advance_to(endpoint, name=name)

    def warrant(self, suspect):
        self.row(1)
        self.enter_menu('N_SHOW_COMPUTER_SAVE_MENU')
        self.enter_menu('N_OPEN_COMPUTER')
        traits = list((ROOT / 'assets/po/N.bin').read_bytes()[self.symbols['SUSPECT_TRAIT_MATRIX']-0x6000+6*suspect:][:6])
        for category, value in enumerate(traits):
            for _ in range(value + 1):
                self.clear(); self.current = self.bp('N_WAIT_COMPUTER_SELECTION')
                self.call('go'); self.call('keys', '\r'); self.stopped('N_WAIT_COMPUTER_SELECTION')
                self.drain_menu_input()
            actual = self.call('read', 27, 6)['bytes']
            if actual[category] != value:
                raise ValueError('Computer trait selection differs')
            self.guard('trait-' + str(category))
            self.row(1)
        result = self.advance_to('N_WAIT_CITY_INPUT', name='warrant')
        if result['case_state'][23] != suspect or result['case_state'][27:33] != traits:
            raise ValueError('Native computer failed to issue the unique warrant')
        self.row(-1)  # Interpol -> Investigate.
        return traits


def launch(name, image, language):
    process, _ = start(name, image, 'approved')
    return process, GameSession(name, language)


def stop(process, session):
    session.exit(); process.wait(timeout=10)
    if process.returncode != 0:
        raise ValueError('Owned gameplay MAME failed normal exit')


def cleanup(process, session):
    if process.poll() is None:
        try:
            session.call('exit'); process.wait(timeout=8)
        except Exception:
            process.kill(); process.wait(timeout=5)


def archive(session):
    destination = test_mode.runtime('approved') / 'gameplay' / session.name
    destination.mkdir(parents=True, exist_ok=True)
    artifacts = {}
    for path in sorted(session.directory.glob('*')):
        if path.suffix in ('.json', '.png', '.hgr') and path.name != 'session.json':
            shutil.copyfile(path, destination / path.name)
            artifacts[path.name] = sha256(path.read_bytes())
    return {'session': session.name, 'language': session.language, 'events': session.events, 'artifacts': artifacts,
            'media_sha256': sha256((session.directory / 'carmen-world.hdv').read_bytes())}


def roster(detective, rank, solved, saved):
    data = bytearray(extract(ROOT / 'carmen-world.po', 'F'))
    data[:19] = detective.encode('ascii').ljust(16, b'\xff') + bytes((rank, solved, saved))
    return bytes(data)


def seed(directory, tag, rank, solved):
    name = 'TEST' + str(rank)
    media = replace_files(ROOT / 'carmen-world.po', directory / (tag + '-seed.po'), {'F': roster(name, rank, solved, 0)})
    process, session = launch('mame-' + tag + '-seed', media, 'english')
    try:
        state = session.boot_game(name)
        if session.call('read', 0x5B, 2)['bytes'] != [rank, solved]:
            raise ValueError('Native seed rank differs')
        if rank == 4 and state[0] != 0:
            raise ValueError('Native Carmen case generator differs')
        stop(process, session)
        return {'name': name, 'rank': rank, 'solved': solved, 'case': state, 'evidence': archive(session)}
    finally:
        cleanup(process, session)


def fixture(base, target, source, state):
    cases = bytearray(extract(base, 'H')); cases[:256] = bytes(state) + bytes(223)
    return replace_files(base, target, {'F': roster(source['name'], source['rank'], source['solved'], 1), 'H': bytes(cases)})


def outcome(directory, tag, base, language, source, kind):
    state = source['case'].copy()
    if kind != 'timeout':
        state[2] = source['rank'] + 3; state[17] = state[16]
    else:
        state[20:22] = [state[18], (state[19]+1) % 24]
        if state[19] == 23:
            raise ValueError('Choose a seed away from midnight for the timeout fixture')
    state[22] = 0; state[23] = 255; state[27:33] = [255]*6
    media = fixture(base, directory / (tag + '-' + kind + '-' + language + '.po'), source, state)
    process, session = launch('mame-' + tag + '-' + kind + '-' + language, media, language)
    try:
        session.boot_game(source['name'], prompt=True, expected=state)
        if kind in ('correct', 'promotion', 'retirement', 'wrong'):
            session.warrant((state[0]+1) % 10 if kind == 'wrong' else state[0])
        if kind == 'timeout':
            result = session.visit(0, 'N_READ_YES_NO_RESPONSE', 'timeout')
        else:
            # First marked visit moves the suspect. The next marked visit
            # triggers the complete arrest animation and report naturally.
            places = session.call('read', 0x9E5A, 3)['bytes']
            session.visit(places.index(1), name='hideout-first-visit')
            places = session.call('read', 0x9E5A, 3)['bytes']
            marked = next(i for i, value in enumerate(places) if value != 255)
            endpoint = 'N_SHOW_IDENTIFY_PROMPT' if kind == 'retirement' else 'N_READ_YES_NO_RESPONSE'
            result = session.visit(marked, endpoint, kind)
        rank_solved = session.call('read', 0x5B, 2)['bytes']
        if kind in ('correct', 'promotion'):
            expected = [source['rank'] + (kind == 'promotion'), source['solved']+1]
            if rank_solved != expected:
                raise ValueError('Arrest rank/progress differs: ' + str(rank_solved))
        if kind in ('no-warrant', 'wrong', 'timeout') and rank_solved != [source['rank'], source['solved']]:
            raise ValueError('Failed case changed progress')
        stop(process, session)
        f, g = extract(session.directory / 'carmen-world.hdv', 'F'), extract(session.directory / 'carmen-world.hdv', 'G')
        if kind == 'retirement' and (f[:19] != bytes([255])*19 or source['name'].encode()+b'\xff' not in g):
            raise ValueError('Retirement did not clear F and add the ASCII name to G')
        return {'kind': kind, 'rank_solved': rank_solved, 'case_state': result['case_state'],
                'F_sha256': sha256(f), 'G_sha256': sha256(g), 'session': archive(session)}
    finally:
        cleanup(process, session)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True, help='new safe session-name prefix')
    parser.add_argument('--resume', type=str, help='reuse completed pairs from an exact-image progress report')
    options = parser.parse_args()
    if not options.tag.replace('-', '').isalnum():
        parser.error('Safe tag required')
    pins = test_mode.identity('approved')
    directory = BUILD / (options.tag + '-gameplay'); directory.mkdir(exist_ok=False)
    if options.resume:
        from pathlib import Path
        prior=read_json(Path(options.resume))
        seeds={int(rank):value for rank,value in prior['seeds'].items()};results=prior['results']
        for pair in results:
            record=pair['editions'][1]['session'];folder=test_mode.runtime('approved')/'gameplay'/record['session']
            guards=[folder/name for name in record['artifacts'] if name.endswith('-approved.json')]
            import json
            if not guards or any(json.loads(read_evidence(path))['image_sha256']!=pins['image_sha256'] for path in guards):
                raise ValueError('Cannot reuse a different-image gameplay report')
            if any(sha256(read_evidence(folder/name))!=digest for name,digest in record['artifacts'].items()):
                raise ValueError('Cannot reuse altered gameplay artifacts')
    else:
        seeds = {rank: seed(directory, options.tag + str(rank), rank, solved) for rank, solved in ((0,0),(1,1),(4,29))}
        results = []
    korean = ROOT / read_json(BUILD / 'approved/manifest.json')['image']
    for kind, rank in (('no-warrant',0), ('wrong',0), ('promotion',0), ('correct',1), ('retirement',4), ('timeout',0)):
        if any(result['kind']==kind for result in results):continue
        pair = [outcome(directory, options.tag, base, language, seeds[rank], kind)
                for language, base in (('english', ROOT / 'carmen-world.po'), ('korean', korean))]
        for field in ('rank_solved', 'F_sha256', 'G_sha256'):
            if pair[0][field] != pair[1][field]:
                raise ValueError('English/Korean gameplay outcome differs: ' + kind + '/' + field)
        results.append({'kind': kind, 'native_outcomes_match': True, 'editions': pair})
        write_json(directory / 'progress.json', {'seeds': seeds, 'results': results})
        print(kind + ': paired native gameplay, progress and F/G match', flush=True)
    write_json(test_mode.runtime('approved') / 'gameplay.json', {'format':1, 'status':'pass', **pins,
        'seeds': seeds, 'results':results, 'scope':'Native-generated rank 0/1/4 routes, cold-restored late-case fixtures; all six computer traits selected by keyboard, complete arrest animations/reports, timeout, promotion, Carmen retirement. Not every random route.'})


if __name__ == '__main__':
    main()
