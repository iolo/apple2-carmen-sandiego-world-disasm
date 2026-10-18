"""Cold-boot native F/G/H save transfers in both English/Korean directions."""

import argparse

from . import test_mode
from .common import BUILD, ROOT, read_json, sha256, write_json
from .gameplay_test import archive, launch, replace_files, stop
from .synthetic_test import saved_media
from .verify_save import extract


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True)
    options = parser.parse_args()
    if not options.tag.replace('-', '').isalnum():
        parser.error('Safe tag required')
    pins = test_mode.identity('approved')
    directory = BUILD / (options.tag + '-save-compat'); directory.mkdir(exist_ok=False)
    english = ROOT / 'carmen-world.po'
    korean_manifest = read_json(BUILD / 'approved/manifest.json')
    korean = ROOT / korean_manifest['image']
    english_manifest = {'files': read_json(ROOT / 'reconstruction/manifest.json')['images']['po']['files']}
    process, session = launch('mame-' + options.tag + '-english-save', english, 'english')
    try:
        session.boot_game('CROSSEN', prompt=True)
        session.investigate(); session.travel_next()
        before = session.save()
        stop(process, session)
        source_evidence = archive(session)
        english_saved = session.directory / 'carmen-world.hdv'
        saved_media(english_saved, before, 'CROSSEN', english_manifest)
    finally:
        if process.poll() is None:
            process.terminate(); process.wait(timeout=10)
    life = read_json(test_mode.runtime('approved') / 'synthetic-text.json')
    korean_saved = BUILD / life['sessions'][0]['session'] / 'carmen-world.hdv'
    cases = [('english-to-korean', english_saved, korean, 'korean', 'CROSSEN', before, english_manifest, source_evidence),
             ('korean-to-english', korean_saved, english, 'english', life['save']['detective'], life['save']['case_state'], korean_manifest, life['sessions'][0])]
    results = []
    for direction, source, target, language, detective, state, source_manifest, source_record in cases:
        payloads = {name: extract(source, name) for name in ('F', 'G', 'H')}
        media = replace_files(target, directory / (direction + '.po'), payloads)
        # Import changed only save payloads, not executable or world data.
        for name in read_json(ROOT / 'reconstruction/manifest.json')['images']['po']['files']:
            if extract(media, name) != (payloads[name] if name in payloads else extract(target, name)):
                raise ValueError('Cross-edition import changed an unrelated payload')
        process, restored = launch('mame-' + options.tag + '-' + direction, media, language)
        try:
            actual = restored.boot_game(detective, prompt=True, expected=state)
            # Capture the complete consumed flag before subsequent gameplay.
            roster = bytes(restored.call('read', 0x0C00, 256)['bytes'])
            slot = next(i for i in range(13) if payloads['F'][i*19:i*19+16].rstrip(b'\xff') == detective.encode())
            expected_roster = bytearray(payloads['F']); expected_roster[slot*19+18] = 0
            if roster != expected_roster:
                raise ValueError('Cross-edition restore changed more than the consumed flag')
            restored.investigate(); restored.travel_next()
            after = restored.guard('cross-edition-after-travel')['case_state']
            stop(process, restored)
            disk = restored.directory / 'carmen-world.hdv'
            if extract(disk, 'F') != expected_roster or extract(disk, 'H') != payloads['H'] or extract(disk, 'G') != payloads['G']:
                raise ValueError('Cross-edition restore/gameplay changed unexpected save bytes')
            for name in read_json(ROOT / 'reconstruction/manifest.json')['images']['po']['files']:
                if name not in payloads and extract(disk, name) != extract(target, name):
                    raise ValueError('Cross-edition gameplay changed an unrelated file')
            results.append({'direction':direction, 'source_sha256':sha256(source.read_bytes()),
                'import_sha256':sha256(media.read_bytes()), 'payloads':{name:sha256(data) for name,data in payloads.items()},
                'source_case':state, 'restored_case':actual, 'after_investigate_and_travel':after,
                'slot':slot, 'consumed_flag_only':True, 'H_padding_preserved':True,
                'source_session':source_record, 'destination_session':archive(restored)})
            print(direction + ': cold restore, case bytes, consumed flag, investigation and planned travel pass', flush=True)
        finally:
            if process.poll() is None:
                process.terminate(); process.wait(timeout=10)
    write_json(test_mode.runtime('approved') / 'save-compatibility.json', {'format':1, 'status':'pass', **pins, 'results':results})


if __name__ == '__main__':
    main()
