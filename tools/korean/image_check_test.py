"""Exercise image-verifier rejection paths on temporary synthetic media only."""

from copy import deepcopy
import shutil
import tempfile

from .common import BUILD, DOCS, ROOT, read_json, sha256, write_json
from .image_check import verify
from .synthetic import normalize_dates

from reconstruct import make_fimg, run


def main():
    source_manifest = BUILD / 'synthetic/manifest.json'
    manifest = read_json(source_manifest)
    image = ROOT / manifest['image']
    baseline = sha256(image.read_bytes())
    results = []
    def rejects(name, expected, manifest_path, image_path):
        try:
            verify(manifest_path, image_path, synthetic=True)
        except ValueError as error:
            if expected not in str(error):
                raise
            results.append({'name': name, 'status': 'pass', 'rejection': str(error)})
            print(name + ': ' + str(error), flush=True)
        else:
            raise AssertionError('Damaged synthetic image/manifest was accepted: ' + name)
    positive = verify(synthetic=True)
    results.append({'name': 'pristine-synthetic', 'status': 'pass', 'files': positive['files_verified'],
                    'targets': positive['po_translation_targets_verified']})
    with tempfile.TemporaryDirectory(prefix='image-check-', dir=BUILD) as temporary:
        from pathlib import Path
        work = Path(temporary)
        damaged = work / 'damaged.po'
        raw = bytearray(image.read_bytes());raw[0] ^= 1;damaged.write_bytes(raw)
        rejects('whole-image-byte-drift', 'Whole image SHA-256 differs', source_manifest, damaged)
        for name, key, value, expected in (
                ('file-length', 'bytes', manifest['files']['C']['bytes'] + 1, 'Image payload differs: C'),
                ('file-metadata', 'metadata', dict(manifest['files']['C']['metadata'], aux='0000'), 'Image metadata differs: C/aux')):
            changed = deepcopy(manifest);changed['files']['C'][key] = value
            path = work / (name + '.json');write_json(path, changed)
            rejects(name, expected, path, image)
        changed = deepcopy(manifest)
        first = next(iter(changed['build_inputs']['sources']))
        changed['build_inputs']['sources'][first] = '0' * 64
        path = work / 'source.json';write_json(path, changed)
        rejects('stale-source-ledger', 'Image build source is stale', path, image)

        # Recompute the outer disk/file hashes after corrupting one font row.
        # The independent pinned-BDF comparison must still reject the disk.
        shutil.copyfile(image, damaged)
        font = bytearray(run('a2kit', 'get', '-d', str(damaged), '-f', 'KF', '-t', 'raw', '--trunc'))
        font[0] ^= 1
        run('a2kit', 'delete', '-d', str(damaged), '-f', 'KF')
        run('a2kit', 'put', '-d', str(damaged), '-f', 'KF', '-t', 'any',
            input_bytes=make_fimg('KF', {'file_image': manifest['files']['KF']['metadata']}, bytes(font)))
        normalize_dates(damaged, {name: {'file_image': item['metadata']} for name, item in manifest['files'].items()})
        changed = deepcopy(manifest)
        changed['image_sha256'] = sha256(damaged.read_bytes())
        changed['files']['KF']['sha256'] = sha256(font)
        path = work / 'font.json';write_json(path, changed)
        rejects('bad-font-with-updated-outer-hashes', 'Installed font file differs', path, damaged)
    if sha256(image.read_bytes()) != baseline:
        raise ValueError('Verifier tests changed the pristine synthetic image')
    write_json(DOCS / 'image-check-rejections.json', {'format': 1, 'status': 'pass',
        'synthetic_image_sha256': baseline, 'probes': results,
        'scope': 'Pristine synthetic verification and temporary corruption/manifest tests. No approval receipt or real-translation media is created.'})
    print('Read-only image verifier rejection tests passed; temporary copies removed', flush=True)


if __name__ == '__main__':
    main()
