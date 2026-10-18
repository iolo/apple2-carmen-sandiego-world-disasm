"""Read or restore detailed verification captures kept in compressed archives."""

import argparse
from functools import lru_cache
import json
from pathlib import Path, PurePosixPath
import tarfile

from .common import DOCS, read_json, sha256


@lru_cache(maxsize=2)
def _members(archive, archive_time, archive_size, index, index_time, index_size):
    manifest = read_json(index)
    if manifest['format'] != 1 or sha256(archive.read_bytes()) != manifest['archive_sha256']:
        raise ValueError('Evidence archive differs: ' + str(archive))
    result = {}
    with tarfile.open(archive, 'r:xz') as stream:
        for member in stream:
            name = PurePosixPath(member.name)
            if (not member.isfile() or name.is_absolute() or '..' in name.parts or
                    str(name) != member.name or member.name in result):
                raise ValueError('Invalid evidence archive member: ' + member.name)
            data = stream.extractfile(member).read()
            expected = manifest['files'].get(member.name)
            if expected != {'bytes': len(data), 'sha256': sha256(data)}:
                raise ValueError('Evidence archive member differs: ' + member.name)
            result[member.name] = data
    if set(result) != set(manifest['files']):
        raise ValueError('Evidence archive member inventory differs')
    return result


def members(directory, stem='artifacts'):
    directory = Path(directory)
    archive, index = directory / (stem + '.tar.xz'), directory / (stem + '.json')
    a, i = archive.stat(), index.stat()
    return _members(archive, a.st_mtime_ns, a.st_size, index, i.st_mtime_ns, i.st_size)


def read(path, *, root=DOCS / 'runtime'):
    """New loose captures take precedence over the archived original run."""
    path, root = Path(path), Path(root)
    if path.is_file():
        return path.read_bytes()
    relative = path.relative_to(root).as_posix()
    try:
        return members(root)[relative]
    except KeyError as error:
        raise FileNotFoundError(path) from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest='action', required=True)
    actions.add_parser('check')
    extract = actions.add_parser('extract')
    extract.add_argument('--archive', choices=('runtime', 'review-history'), default='runtime')
    extract.add_argument('--output', type=Path, required=True, help='new directory to restore the archived paths into')
    options = parser.parse_args()
    if options.action == 'check':
        for directory, stem in ((DOCS/'runtime', 'artifacts'), (DOCS/'review', 'history')):
            print(f'{stem}: {len(members(directory, stem))} archived files verified')
    else:
        directory, stem = ((DOCS/'runtime', 'artifacts') if options.archive == 'runtime' else (DOCS/'review', 'history'))
        files = members(directory, stem)
        options.output.mkdir(parents=True, exist_ok=False)
        for name, data in files.items():
            path = options.output / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        print(f'Restored {len(files)} files into {options.output}')


if __name__ == '__main__':
    main()
