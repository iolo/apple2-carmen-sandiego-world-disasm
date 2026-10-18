"""Explicit media, fixture and evidence selection for native runtime checks."""

from .common import BUILD, DOCS, ROOT, read_json, sha256


def argument(parser):
    parser.add_argument('--mode', choices=('synthetic', 'approved'), default='synthetic')


def directory(mode='synthetic'):
    if mode not in ('synthetic', 'approved'):
        raise ValueError('Unknown runtime test mode')
    return BUILD / mode


def runtime(mode='synthetic'):
    return DOCS / ('runtime/approved' if mode == 'approved' else 'runtime')


def identity(mode='synthetic'):
    manifest = read_json(directory(mode) / 'manifest.json')
    if manifest['mode'] != mode or sha256((ROOT / manifest['image']).read_bytes()) != manifest['image_sha256']:
        raise ValueError('Runtime media differs from the selected build')
    if mode == 'synthetic':
        return {'synthetic_image_sha256': manifest['image_sha256']}
    from .approval import require
    receipt = require()
    digest = sha256((ROOT / 'assets/korean/approval.json').read_bytes())
    if manifest['catalog_sha256'] != receipt['catalog_sha256'] or manifest['build_inputs']['approval_sha256'] != digest:
        raise ValueError('Runtime build differs from human approval')
    return {'mode': mode, 'image_sha256': manifest['image_sha256'],
            'catalog_sha256': manifest['catalog_sha256'], 'approval_sha256': digest}


def text(value, encoding, mode='synthetic'):
    return encoding.synthetic(value) if mode == 'synthetic' else value


def bootstrap(session):
    return session.lua("_G.carmen_korean_mode='" + session.mode + "'; return dofile('tools/korean/synthetic_runtime.lua')")
