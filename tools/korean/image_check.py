"""Read-only verification of complete synthetic or human-approved disk bytes.

This validates a pristine build image. Emulator sessions use writable copies;
their legitimate F/G/H changes must be audited by the separate save tests.
"""

import argparse
import json
from pathlib import Path
import sys

from .approval import require
from .catalog import CATALOG
from .captions import half_width
from .clock import compile_clock
from .common import BUILD, DOCS, ROOT, original_inputs, read_json, sha256, write_json
from .encoding import GameEncoding
from .font import hgr_rows, load_bdf

sys.path.insert(0, str(ROOT / 'tools'))
from prodos_inventory import root_inventory
from reconstruct import IMAGES, run


def verify(manifest_path=None, image_path=None, *, synthetic=False):
    receipt = None if synthetic else require()
    mode = 'synthetic' if synthetic else 'approved'
    manifest_path = Path(manifest_path) if manifest_path else BUILD / mode / 'manifest.json'
    manifest = read_json(manifest_path)
    if manifest['mode'] != mode:
        raise ValueError('Image verification mode differs from the build manifest')
    catalog = read_json(CATALOG)
    if sha256(CATALOG.read_bytes()) != manifest['catalog_sha256']:
        raise ValueError('Image catalog is stale')
    if manifest['original_inputs'] != original_inputs():
        raise ValueError('Original input identities differ')
    inputs = manifest['build_inputs']
    for name, digest in inputs['sources'].items():
        if sha256((ROOT / name).read_bytes()) != digest:
            raise ValueError('Image build source is stale: ' + name)
    if sha256((ROOT / 'assets/korean/font/source.json').read_bytes()) != inputs['font_source_sha256']:
        raise ValueError('Font source pin is stale')
    if receipt is not None:
        if receipt != manifest['human_approval'] or inputs['approval_sha256'] != sha256((ROOT / 'assets/korean/approval.json').read_bytes()):
            raise ValueError('Image approval differs from the current human receipt')
    image_path = Path(image_path) if image_path else ROOT / manifest['image']
    raw = image_path.read_bytes()
    if sha256(raw) != manifest['image_sha256']:
        raise ValueError('Whole image SHA-256 differs')
    if len(raw) != 1600 * 512:
        raise ValueError('Image is not an 800K ProDOS disk')
    inventory = root_inventory(lambda block: raw[block * 512:(block + 1) * 512])
    names = set(IMAGES['po']['files']) | {'KL', 'KF'}
    if set(inventory['files']) != names or set(manifest['files']) != names or inventory['malformed_unused_entries']:
        raise ValueError('Image directory/file inventory differs')
    if inventory['volume'] != 'CARMEN.WORLD':
        raise ValueError('Image volume name differs')
    volume = 2 * 512
    total = int.from_bytes(raw[volume + 41:volume + 43], 'little')
    bitmap = int.from_bytes(raw[volume + 39:volume + 41], 'little') * 512
    if total != 1600 or bitmap + 200 > len(raw):
        raise ValueError('Invalid image allocation bitmap')
    free = sum(bool(raw[bitmap + block // 8] & (0x80 >> (block % 8))) for block in range(total))
    if free != manifest['disk']['free_blocks'] or free <= 0:
        raise ValueError('Image free-block count differs')
    original = read_json(ROOT / 'reconstruction/manifest.json')['images']['po']['files']
    data = {}
    changed = {'WORLD.SYSTEM', 'B', 'C', 'D', 'I', 'K', 'N', 'R', 'S2', 'KL', 'KF'}
    for name in sorted(names):
        record = manifest['files'][name]
        payload = run('a2kit', 'get', '-d', str(image_path), '-f', name, '-t', 'raw', '--trunc')
        if len(payload) != record['bytes'] or sha256(payload) != record['sha256']:
            raise ValueError('Image payload differs: ' + name)
        metadata = json.loads(run('a2kit', 'get', '-d', str(image_path), '-f', name, '-t', 'any'))
        for key in ('fs_type', 'aux', 'eof', 'access', 'created', 'modified', 'version', 'min_version'):
            if metadata[key] != record['metadata'][key]:
                raise ValueError(f'Image metadata differs: {name}/{key}')
        if name not in changed and sha256(payload) != original[name]['sha256']:
            raise ValueError('Excluded/unmodified original file changed: ' + name)
        data[name] = payload
    details = read_json(DOCS / f'{mode}-text-assets.json')
    if details['mode'] != mode or details['catalog_sha256'] != manifest['catalog_sha256']:
        raise ValueError('Compiled text evidence is stale')
    for name, record in details['files'].items():
        if len(data[name]) != record['bytes'] or sha256(data[name]) != record['sha256']:
            raise ValueError('Image differs from its compiled text asset: ' + name)

    enc = GameEncoding.from_catalog(catalog)
    entries = {entry['id']: entry for entry in catalog['entries']
               if any(ref['variant'] == 'po' for ref in entry['references'])}
    covered = set()
    def payload(identifier):
        covered.add(identifier)
        return enc.entry(entries[identifier], synthetic=synthetic)
    def group(prefix):
        return b''.join(payload(identifier) for identifier in sorted(entries) if identifier.startswith(prefix))
    def span(name, address, expected):
        base = int.from_bytes(bytes.fromhex(manifest['files'][name]['metadata']['aux']), 'little')
        offset = address - base
        if offset < 0 or offset + len(expected) > len(data[name]) or data[name][offset:offset + len(expected)] != expected:
            raise ValueError(f'Encoded text/data differs: {name}/${address:04X}')

    glyphs = load_bdf()
    font = b''.join(hgr_rows(glyphs, character) for character in enc.characters)
    if data['KF'] != font or sha256(font) != inputs['font_sha256']:
        raise ValueError('Installed font file differs from pinned BDF cells')
    for name in ('I', 'K'):
        if data[name] != group(name.lower() + '.'):
            raise ValueError('Auxiliary text differs from the catalog: ' + name)
    ui = group('c.ui.')
    span('C', 0xE000, ui + bytes(3072 - len(ui)))
    names_data = b''.join(group('c.' + prefix + '.') for prefix in ('cities', 'suspects', 'detective_ranks', 'weekdays', 'weekday_suffixes'))
    span('C', 0xDB11, names_data + bytes(495 - len(names_data)))
    traits = b''.join(group('c.clue.' + prefix + '.') for prefix in ('sex', 'hobbies', 'hair', 'features', 'vehicles', 'food'))
    span('C', 0xDD7C, traits + bytes(0xE000 - 0xDD7C - len(traits)))
    symbols = details['files']['C']['symbols']
    for sex in ('he', 'she'):
        span('C', symbols['C_PRONOUN_' + sex.upper()], payload('c.service.' + sex))
    old_c = (ROOT / 'assets/po/C.bin').read_bytes()
    start = end = 0xDC0F - 0xD200
    for _ in range(15):
        end = old_c.index(0, end) + 1
    span('C', 0xD7BD, old_c[start:end])
    for low, high in ((0xD400, 0xD7BD), (0xDD00, 0xDD7C), (0xEC00, 0xF979)):
        span('C', low, old_c[low - 0xD200:high - 0xD200])
    clock, _ = compile_clock(enc, entries, synthetic=synthetic)
    if data['D'] != clock:
        raise ValueError('Clock/native font ABI differs')
    covered.update(('bitmap.d.am', 'bitmap.d.pm'))
    span('N', details['files']['N']['save_dialog_address'], payload('n.save_dialog'))
    span('R', details['files']['R']['intro_address'], group('r.intro.'))
    old_n = (ROOT / 'assets/po/N.bin').read_bytes()
    plural = bytes.fromhex('a4aca9739900a0e6ac')
    if old_n.count(plural) != 1 or payload('n.plural_suffix'):
        raise ValueError('Unexpected original plural-span contract')
    span('N', 0x6000 + old_n.index(plural), bytes([0xEA]) * 9)

    s2 = data['S2']
    offsets = [int.from_bytes(s2[i:i + 3], 'little') for i in range(0, 192, 3)]
    if offsets[0] != 192 or offsets[30] != len(s2) or any(offsets[31:]) or any(a >= b for a, b in zip(offsets[:30], offsets[1:31])):
        raise ValueError('S2 30-record/24-bit offset table differs')
    old_s2 = (ROOT / 'assets/po/S2.bin').read_bytes()
    old_offsets = [int.from_bytes(old_s2[i:i + 3], 'little') for i in range(0, 93, 3)]
    city_reports = []
    for number in range(30):
        fields = {}
        for entry in entries.values():
            for ref in entry['references']:
                if ref['variant'] == 'po' and ref['file'] == 'S2' and ref.get('record') == number:
                    fields[ref['string_index']] = entry['id']
        if sorted(fields) != list(range(len(fields))):
            raise ValueError('S2 raw-NUL string indexes differ')
        encoded_fields = [payload(fields[i]) for i in range(len(fields))]
        expected = b''.join(encoded_fields)
        record = s2[offsets[number]:offsets[number + 1]]
        boundary = int.from_bytes(record[:2], 'little')
        old = old_s2[old_offsets[number]:old_offsets[number + 1]]
        picture = old[int.from_bytes(old[:2], 'little'):]
        if boundary != 2 + len(expected) or record[2:boundary] != expected or record[boundary:] != picture:
            raise ValueError('S2 city text/boundary/original picture differs: ' + str(number))
        if len(expected) > 1792 or len(picture) + 1 > 3072:
            raise ValueError('S2 native text/image buffer exceeded')
        cursor, clue_sizes = 3, []
        counts = old_n[0x8D78 - 0x6000 + number * 12:0x8D78 - 0x6000 + (number + 1) * 12]
        for count in counts:
            if cursor + count > len(encoded_fields):
                raise ValueError('S2 native clue selector exceeds its fields')
            if count:
                clue_sizes.append(max(map(len, encoded_fields[cursor:cursor + count])))
            cursor += count
        description = max(map(len, encoded_fields[:3]))
        three_clues = sum(sorted(clue_sizes, reverse=True)[:3])
        if description > 256 or three_clues > 512:
            raise ValueError('S2 selected description/clue buffer exceeded')
        city_reports.append({'city': number, 'strings': len(fields), 'text_bytes': len(expected),
                             'picture_bytes': len(picture), 'picture_sha256': sha256(picture),
                             'selected_description_with_nul': description, 'three_clues_with_nuls': three_clues})

    display = enc.synthetic if synthetic else lambda value: value
    captions = details['captions']
    for module, item in captions['modules'].items():
        for category, address in item['command_pointers'].items():
            cursor = address - 0x6000
            for identifier, layout in captions['layout'].items():
                if layout['group'] != category:
                    continue
                covered.add(identifier)
                value = entries[identifier]['translation']
                lines = value.split(' ', 1) if identifier == 'bitmap.s.agency' else value.split('\n')
                encoded = b''.join(enc.encode(display(line)) + b'\0' for line in lines)
                left, right, top, bottom = layout['rectangle']
                clear = bytes((int(layout['white_background']), left // 2, (right - 2) // 2, top, bottom - 1))
                if data[module][cursor:cursor + 5] != clear:
                    raise ValueError('Caption rectangle command differs: ' + identifier)
                cursor += 5
                for line in layout['lines']:
                    command = data[module][cursor:cursor + 5]
                    if (len(command) != 5 or command[0] != 2 or command[2] != line['top'] or
                            command[1] * 2 != line['left'] + half_width(line['advance_width'])):
                        raise ValueError('Caption text command differs: ' + identifier)
                    pointer = int.from_bytes(command[3:5], 'little')
                    span(module, pointer - line['pointer_offset'], encoded)
                    cursor += 5
            if data[module][cursor] != 255:
                raise ValueError('Caption command terminator differs')
    for entry in entries.values():
        for ref in entry['references']:
            if ref['variant'] == 'po' and ref['output_mode'] == 'TEXT':
                if entry['translatable'] or bytes.fromhex(ref['original_hex']) not in data[ref['file']]:
                    raise ValueError('English TEXT MODE exclusion differs: ' + entry['id'])
    missing = sorted(entry['id'] for entry in entries.values() if entry['translatable'] and entry['id'] not in covered)
    if missing:
        raise ValueError('Unverified image translation IDs: ' + ', '.join(missing))
    if sha256(image_path.read_bytes()) != manifest['image_sha256']:
        raise ValueError('Image changed during read-only verification')
    return {'format': 1, 'status': 'pass', 'mode': mode, 'catalog_sha256': manifest['catalog_sha256'],
            'verifier_sha256': sha256(Path(__file__).read_bytes()),
            'image_sha256': manifest['image_sha256'], 'files_verified': len(names), 'free_blocks': free,
            'po_translation_targets_verified': sum(entry['translatable'] for entry in entries.values()),
            'font_bytes': len(font), 'cities': city_reports,
            'scope': 'Pristine image hashes, source pins, payloads/metadata, original exclusions and all 800K translation data. No CPU/gameplay or cross-edition save execution is claimed.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--synthetic', action='store_true', help='Check only the preapproval synthetic build')
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--image', type=Path)
    options = parser.parse_args()
    try:
        report = verify(options.manifest, options.image, synthetic=options.synthetic)
    except (ValueError, KeyError, OSError, TypeError, RuntimeError) as error:
        parser.error(str(error))
    write_json(DOCS / f"{report['mode']}-image-check.json", report)
    print(f"Verified {report['files_verified']} files and all {report['po_translation_targets_verified']} 800K translation targets; read-only image check passes")


if __name__ == '__main__':
    main()
