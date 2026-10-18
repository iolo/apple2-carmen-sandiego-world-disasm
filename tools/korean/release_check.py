"""Audit completed approved-build evidence without rerunning emulation."""

import json
import shutil
from pathlib import Path

from . import test_mode
from .common import BUILD, DOCS, ROOT, original_inputs, read_json, sha256, write_json
from .image_check import verify
from .evidence import read as read_evidence


def machine_profile(name, previous, *, workspace=ROOT):
    """Keep auditing pinned profiles after disposable MAME folders are removed."""
    if Path(name).name != name or name in ('.', '..'):
        raise ValueError('Invalid runtime session name')
    workspace = Path(workspace)
    live = workspace / 'build/korean' / name / 'session.json'
    relative = f'docs/korean/runtime/approved/profiles/{name}.json'
    archived = workspace / relative
    if live.is_file():
        data = live.read_bytes()
    else:
        expected = previous.get(relative)
        if expected is None:
            raise ValueError('Archived machine profile is not pinned: ' + name)
        data = read_evidence(archived, root=workspace/'docs/korean/runtime')
        if sha256(data) != expected:
            raise ValueError('Archived machine profile differs: ' + name)
    profile = json.loads(data)
    if (profile['machine'], profile['main_kib'], profile['auxiliary_kib']) != ('apple2e', 64, 64):
        raise ValueError('Runtime machine profile differs')
    process = Path(f"/proc/{profile['pid']}/cmdline")
    if process.exists() and str(live.parent).encode() in process.read_bytes():
        raise ValueError('Owned runtime MAME is still running: ' + name)
    if live.is_file():
        archived.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(live, archived)
    return relative, sha256(data)


def main():
    pins = test_mode.identity('approved')
    verify()
    base = test_mode.runtime('approved')
    profiles = {}
    previous_path = DOCS / 'release-check.json'
    previous = read_json(previous_path) if previous_path.exists() else {}
    previous_profiles = (previous.get('machine_profiles', {})
                         if all(previous.get(k) == v for k,v in pins.items()) else {})

    def artifacts(value, directory):
        if isinstance(value, list):
            for item in value: artifacts(item, directory)
        if not isinstance(value, dict): return
        if value.get('language') and value.get('session'):
            directory = base / 'gameplay' / value['session']
        elif 'image_sha256_after_session' in value:
            directory = base / 'synthetic-text' / value['session']
        for name, digest in value.get('artifacts', {}).items():
            path = directory / name
            if sha256(read_evidence(path)) != digest:
                raise ValueError('Runtime artifact differs: ' + str(path))
        name = value.get('session')
        if isinstance(name, str):
            relative, digest = machine_profile(name, previous_profiles)
            profiles[relative] = digest
        for item in value.values():
            if isinstance(item, (dict,list)): artifacts(item, directory)

    reports = {}
    for name in ('synthetic-text', 'native-readers', 'native-clock', 'native-captions', 'native-messages', 'native-cities',
                 'gameplay', 'save-compatibility', 'disk-errors', 'visual'):
        path = base / (name + '.json'); report = read_json(path)
        if report['status'] != 'pass' or any(report.get(k) != v for k,v in pins.items()):
            raise ValueError('Approved runtime identity differs: ' + name)
        artifacts(report, base / name)
        reports[str(path.relative_to(ROOT))] = sha256(path.read_bytes())
    font = read_json(DOCS/'runtime/native-font.json')
    manifest = read_json(BUILD/'approved/manifest.json')
    if (font['font_sha256'] != manifest['files']['KF']['sha256'] or
            font['library_sha256'] != sha256((BUILD/'library/KL.bin').read_bytes())):
        raise ValueError('Base native decoder proof belongs to a different font/library')
    for name in ('native-font','native-renderers'):
        path=DOCS/f'runtime/{name}.json';report=read_json(path)
        if report['status']!='pass':raise ValueError('Base native component proof failed')
        artifacts(report,DOCS/'runtime'/name)
        reports[str(path.relative_to(ROOT))]=sha256(path.read_bytes())
    gameplay = read_json(base / 'gameplay.json')
    if {r['kind'] for r in gameplay['results']} != {'no-warrant','wrong','promotion','correct','retirement','timeout'}:
        raise ValueError('Missing required gameplay branch')
    for pair in gameplay['results']:
        english, korean = pair['editions']
        fields = ('rank_solved','F_sha256','G_sha256') + (() if pair['kind']=='retirement' else ('case_state',))
        if any(english[field] != korean[field] for field in fields):
            raise ValueError('Paired native outcomes differ: ' + pair['kind'])
    if len(read_json(base/'native-cities.json')['results']) != 60:
        raise ValueError('City read coverage differs')
    if len(read_json(base/'save-compatibility.json')['results']) != 2:
        raise ValueError('Bidirectional save certification missing')
    clean = read_json(DOCS/'clean-build.json')
    if clean['status']!='pass' or clean['image_sha256']!=pins['image_sha256'] or clean['copied_build_artifacts']:
        raise ValueError('Clean-source reproduction missing')
    english = read_json(DOCS/'english-baseline.json')
    if len(english['commands']) != 3 or any(c['exit_code'] for c in english['commands']):
        raise ValueError('English regression missing')
    for name in ('clean-build','english-baseline','approved-image-check','image-check-rejections'):
        path=DOCS/(name+'.json');reports[str(path.relative_to(ROOT))]=sha256(path.read_bytes())
    report={'format':1,'status':'pass',**pins,'original_inputs':original_inputs(),'reports':reports,'machine_profiles':profiles,
        'all_nonretirement_case_bytes_match_english':True,
        'retirement_progress_roster_and_hall_match_english':True,
        'limits':['Not every random route, clue pick, roster capacity, name editing or hall replacement branch was played.',
                  'All city/trait/message layouts and every 800K translation are covered statically; native extrema/readers/city reads supplement representative gameplay.',
                  'Fourteen retained S2 tails and unused/floppy-only UI have offline coverage, not live branch evidence.',
                  '140K Korean port and floppy save interchange remain outside scope.']}
    write_json(DOCS/'release-check.json',report)
    print('Approved release evidence, native outcomes, artifacts, profiles and English regressions pass')


if __name__=='__main__':main()
