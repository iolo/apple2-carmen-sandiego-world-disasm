"""Compressed evidence keeps exact captures available to existing audits."""

import io
from pathlib import Path
import tarfile
import tempfile
import unittest

from korean.common import sha256, write_json
from korean.evidence import members, read


class EvidenceArchiveTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def archive(self, files, expected=None):
        target = self.root/'artifacts.tar.xz'
        with tarfile.open(target, 'w:xz') as stream:
            for name, data in files.items():
                info = tarfile.TarInfo(name); info.size = len(data)
                stream.addfile(info, io.BytesIO(data))
        write_json(self.root/'artifacts.json', {'format':1, 'archive_sha256':sha256(target.read_bytes()),
            'files':expected if expected is not None else
                    {name:{'bytes':len(data),'sha256':sha256(data)} for name,data in files.items()}})

    def test_archived_bytes_and_new_loose_captures_are_read_without_extraction(self):
        self.archive({'session/output.bin': b'original bytes'})
        path=self.root/'session/output.bin'
        self.assertEqual(read(path,root=self.root),b'original bytes')
        self.assertFalse(path.exists())
        path.parent.mkdir();path.write_bytes(b'new run')
        self.assertEqual(read(path,root=self.root),b'new run')

    def test_archive_corruption_is_rejected(self):
        self.archive({'output.bin':b'bytes'})
        with (self.root/'artifacts.tar.xz').open('ab') as stream:stream.write(b'corruption')
        with self.assertRaisesRegex(ValueError,'archive differs'):members(self.root)

    def test_recomputed_outer_hash_does_not_hide_bad_members(self):
        self.archive({'output.bin':b'modified'}, {'output.bin':{'bytes':8,'sha256':sha256(b'original')}})
        with self.assertRaisesRegex(ValueError,'member differs'):members(self.root)

    def test_unsafe_paths_and_incomplete_inventory_are_rejected(self):
        self.archive({'../outside.bin':b'bytes'})
        with self.assertRaisesRegex(ValueError,'Invalid evidence'):members(self.root)
        self.archive({}, {'missing.bin':{'bytes':5,'sha256':sha256(b'bytes')}})
        with self.assertRaisesRegex(ValueError,'inventory differs'):members(self.root)
