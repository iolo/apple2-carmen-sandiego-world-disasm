"""Archived runtime evidence must remain verifiable after scratch cleanup."""

from pathlib import Path
import shutil
import tempfile
import unittest

from korean.common import write_json
from korean.release_check import machine_profile


class RuntimeProfileTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.live = self.root / 'build/korean/test-session/session.json'
        self.profile = {'machine': 'apple2e', 'main_kib': 64, 'auxiliary_kib': 64, 'pid': 0}
        write_json(self.live, self.profile)

    def test_pinned_profile_survives_removal_of_disposable_session(self):
        relative, digest = machine_profile('test-session', {}, workspace=self.root)
        shutil.rmtree(self.live.parent)
        self.assertEqual(machine_profile('test-session', {relative: digest}, workspace=self.root),
                         (relative, digest))

    def test_missing_unpinned_and_tampered_archives_fail(self):
        relative, digest = machine_profile('test-session', {}, workspace=self.root)
        shutil.rmtree(self.live.parent)
        with self.assertRaisesRegex(ValueError, 'not pinned'):
            machine_profile('test-session', {}, workspace=self.root)
        archive = self.root / relative
        archive.write_bytes(archive.read_bytes() + b'\n')
        with self.assertRaisesRegex(ValueError, 'differs'):
            machine_profile('test-session', {relative: digest}, workspace=self.root)
        archive.unlink()
        with self.assertRaises(FileNotFoundError):
            machine_profile('test-session', {relative: digest}, workspace=self.root)

    def test_wrong_machine_and_session_paths_fail(self):
        self.profile['auxiliary_kib'] = 128
        write_json(self.live, self.profile)
        with self.assertRaisesRegex(ValueError, 'profile differs'):
            machine_profile('test-session', {}, workspace=self.root)
        for name in ('..', '../other-session', '/tmp/session'):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'session name'):
                machine_profile(name, {}, workspace=self.root)
