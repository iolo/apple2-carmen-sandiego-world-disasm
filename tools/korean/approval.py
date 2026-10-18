"""Verify an explicit human receipt against the exact frozen review bundle.

Run `record` only after the human has actually approved the whole translation
version. Passing technical checks never creates approval. The frozen catalog
keeps its reviewed bytes/status labels; this separate receipt is authoritative.
"""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path

from .common import ROOT, read_json, sha256, write_json


def bundle(review_manifest, *, workspace=ROOT):
    workspace = Path(workspace).resolve()
    review_manifest = Path(review_manifest).resolve()
    review_manifest.relative_to(workspace / 'docs/korean/review')
    manifest = read_json(review_manifest)
    files = manifest['files']
    digest = sha256(json.dumps(files, sort_keys=True, separators=(',', ':')).encode())
    if digest != manifest['bundle_sha256']:
        raise ValueError('Review bundle manifest changed')
    directory = review_manifest.parent
    for name, expected in files.items():
        path = (directory / name).resolve()
        path.relative_to(directory)
        if not path.is_file() or sha256(path.read_bytes()) != expected:
            raise ValueError('Reviewed artifact changed: ' + name)
    live = {'catalog.json': 'assets/korean/catalog.json',
            'glossary.json': 'assets/korean/glossary.json',
            'review-notes.json': 'assets/korean/review-notes.json',
            'font-source.json': 'assets/korean/font/source.json',
            'FONT-LICENSE.txt': 'assets/korean/font/LICENSE.txt'}
    for name, path in live.items():
        if sha256((workspace / path).read_bytes()) != files[name]:
            raise ValueError('Current input differs from human-review version: ' + path)
    catalog_path = workspace / live['catalog.json']
    if sha256(catalog_path.read_bytes()) != manifest['catalog_sha256']:
        raise ValueError('Reviewed catalog hash differs')
    catalog = read_json(catalog_path)
    identifiers = sorted(entry['id'] for entry in catalog['entries'] if entry['translatable'])
    if len(identifiers) != len(set(identifiers)) or len(identifiers) != manifest['translation_targets']:
        raise ValueError('Reviewed translation scope differs')
    if any(entry['translation'] is None for entry in catalog['entries'] if entry['translatable']):
        raise ValueError('Reviewed translation is missing')
    return manifest, identifiers


def validate(receipt, *, workspace=ROOT):
    workspace = Path(workspace).resolve()
    if receipt.get('format') != 1 or receipt.get('status') != 'approved' or receipt.get('scope') != 'all_catalog_translations':
        raise ValueError('Whole-catalog human approval is required')
    if not receipt.get('reviewer', '').strip() or not receipt.get('statement', '').strip():
        raise ValueError('Human reviewer and actual approval statement are required')
    try:
        moment = datetime.fromisoformat(receipt['approved_at'])
        if moment.utcoffset() is None:
            raise ValueError('timezone missing')
    except (ValueError, KeyError, TypeError) as error:
        raise ValueError('Approval timestamp must include its timezone') from error
    if receipt.get('open_issues') != []:
        raise ValueError('Unresolved review issues prevent a production build')
    relative = Path(receipt['review_manifest'])
    if relative.is_absolute():
        raise ValueError('Review receipt must use a workspace-relative manifest')
    path = workspace / relative
    manifest, identifiers = bundle(path, workspace=workspace)
    if sha256(path.read_bytes()) != receipt['review_manifest_sha256']:
        raise ValueError('The approved review manifest changed')
    if (receipt['catalog_sha256'] != manifest['catalog_sha256'] or
            receipt['bundle_sha256'] != manifest['bundle_sha256']):
        raise ValueError('Approval belongs to a different catalog/review bundle')
    if receipt.get('approved_ids') != identifiers:
        raise ValueError('Approval does not cover every exact translation ID')
    return receipt


def require(*, workspace=ROOT):
    path = Path(workspace) / 'assets/korean/approval.json'
    if not path.is_file():
        raise ValueError('Human approval is missing. Review the frozen bundle and record explicit whole-catalog approval before building real translations.')
    return validate(read_json(path), workspace=workspace)


def record(review_manifest, reviewer, statement, *, approved_at=None, workspace=ROOT):
    """Record a human response; callers must never infer or fabricate it."""
    workspace = Path(workspace).resolve()
    review_manifest = Path(review_manifest).resolve()
    manifest, identifiers = bundle(review_manifest, workspace=workspace)
    receipt = {'format': 1, 'status': 'approved', 'scope': 'all_catalog_translations',
               'reviewer': reviewer, 'approved_at': approved_at or datetime.now(timezone.utc).isoformat(),
               'statement': statement, 'open_issues': [],
               'review_manifest': str(review_manifest.relative_to(workspace)),
               'review_manifest_sha256': sha256(review_manifest.read_bytes()),
               'catalog_sha256': manifest['catalog_sha256'], 'bundle_sha256': manifest['bundle_sha256'],
               'approved_ids': identifiers}
    validate(receipt, workspace=workspace)
    path = workspace / 'assets/korean/approval.json'
    pending = path.with_suffix('.json.tmp')
    write_json(pending, receipt)
    pending.replace(path)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest='action', required=True)
    actions.add_parser('check')
    recording = actions.add_parser('record')
    recording.add_argument('--review-manifest', type=Path, required=True)
    recording.add_argument('--reviewer', required=True)
    recording.add_argument('--statement-file', type=Path, required=True,
                           help='Exact human approval response, not an agent summary')
    recording.add_argument('--all-translations', action='store_true', required=True,
                           help='The human explicitly approved the whole catalog version')
    options = parser.parse_args()
    try:
        if options.action == 'check':
            receipt = require()
        else:
            receipt = record(options.review_manifest, options.reviewer, options.statement_file.read_text(encoding='utf-8'))
    except (ValueError, KeyError, OSError, TypeError) as error:
        parser.error(str(error))
    print('Verified human approval:', receipt['catalog_sha256'])


if __name__ == '__main__':
    main()
