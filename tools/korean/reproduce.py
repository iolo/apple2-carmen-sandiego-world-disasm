"""Rebuild approved media in a fresh source copy with no build artifacts."""

import shutil
import subprocess
import tempfile
from pathlib import Path

from .common import BUILD, DOCS, ROOT, read_json, sha256, write_json
from .test_mode import identity


def main():
    pins = identity('approved')
    log = BUILD / 'clean-build.log'
    with tempfile.TemporaryDirectory(prefix='carmen-ko-clean-') as temporary:
        source = Path(temporary) / 'source'
        shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('build', '.git', '__pycache__', '*.pyc'))
        assert not (source / 'build').exists()
        with log.open('w') as output:
            for command in (['make', 'korean'], ['make', 'korean'], ['make', 'korean-image-check']):
                subprocess.run(command, cwd=source, stdout=output, stderr=subprocess.STDOUT, check=True)
        manifest = read_json(source / 'build/korean/approved/manifest.json')
        image = source / manifest['image']
        if sha256(image.read_bytes()) != pins['image_sha256'] or manifest['repeated_build_identical'] is not True:
            raise ValueError('Fresh source rebuild differs from the approved media')
        check = read_json(source / 'docs/korean/approved-image-check.json')
        if check['status'] != 'pass':
            raise ValueError('Fresh source read-only image verification failed')
        write_json(DOCS / 'clean-build.json', {'format': 1, 'status': 'pass', **pins,
            'fresh_source_copy': True, 'copied_build_artifacts': False,
            'two_builds_identical': True, 'read_only_image_check': 'pass',
            'log_sha256': sha256(log.read_bytes()), 'temporary_source_removed': True})
    print('Fresh source rebuild and repeated bytes match approved image')


if __name__ == '__main__':
    main()
