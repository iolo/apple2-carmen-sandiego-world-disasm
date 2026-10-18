"""Approval boundaries use isolated fictional catalogs, never real receipts/media."""

from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from korean import approval, game_text, image_check, production, synthetic
from korean.common import sha256, write_json
from korean.clock import compile_clock
from korean.encoding import GameEncoding


class ApprovalTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.review = self.root / 'docs/korean/review/fictional-test-only'
        self.review.mkdir(parents=True)
        self.catalog = {'approval': None, 'entries': [
            {'id': 'fictional.first', 'translatable': True, 'translation': '가', 'status': 'draft'},
            {'id': 'fictional.empty', 'translatable': True, 'translation': '', 'status': 'draft'}]}
        self.live = {
            'catalog.json': 'assets/korean/catalog.json',
            'glossary.json': 'assets/korean/glossary.json',
            'review-notes.json': 'assets/korean/review-notes.json',
            'font-source.json': 'assets/korean/font/source.json',
            'FONT-LICENSE.txt': 'assets/korean/font/LICENSE.txt'}
        for name, relative in self.live.items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(self.catalog, ensure_ascii=False) if name == 'catalog.json' else 'fictional test fixture')
            (self.review / name).write_bytes(path.read_bytes())
        self.files = {name: sha256((self.review / name).read_bytes()) for name in self.live}
        self.manifest = self.review / 'manifest.json'
        write_json(self.manifest, {'files': self.files, 'catalog_sha256': self.files['catalog.json'],
                   'bundle_sha256': sha256(json.dumps(self.files, sort_keys=True, separators=(',', ':')).encode()),
                   'translation_targets': 2})

    def receipt(self):
        # No actual workspace approval is created by these unit tests.
        return approval.record(self.manifest, 'fictional test reviewer', 'TEST FIXTURE ONLY — not human approval',
                               approved_at='2026-01-01T00:00:00+00:00', workspace=self.root)

    def test_missing_approval_rejects_without_creating_output(self):
        with self.assertRaisesRegex(ValueError, 'Human approval is missing'):
            approval.require(workspace=self.root)
        self.assertFalse((self.root / 'build').exists())
        self.assertFalse((self.root / 'assets/korean/approval.json').exists())

    def test_receipt_covers_every_id_and_preserves_the_reviewed_catalog_bytes(self):
        before = (self.root / 'assets/korean/catalog.json').read_bytes()
        receipt = self.receipt()
        self.assertEqual(approval.require(workspace=self.root), receipt)
        self.assertEqual(receipt['approved_ids'], ['fictional.empty', 'fictional.first'])
        self.assertEqual((self.root / 'assets/korean/catalog.json').read_bytes(), before)

    def test_any_live_catalog_or_glossary_edit_invalidates_approval(self):
        receipt = self.receipt()
        for relative in ('assets/korean/catalog.json', 'assets/korean/glossary.json'):
            path = self.root / relative
            original = path.read_bytes()
            path.write_bytes(original + b'\n')
            with self.subTest(relative=relative), self.assertRaisesRegex(ValueError, 'Current input differs'):
                approval.validate(receipt, workspace=self.root)
            path.write_bytes(original)

    def test_tampered_snapshot_or_manifest_is_rejected(self):
        receipt = self.receipt()
        path = self.review / 'review-notes.json'
        original = path.read_bytes()
        path.write_bytes(b'changed after review')
        with self.assertRaisesRegex(ValueError, 'Reviewed artifact changed'):
            approval.validate(receipt, workspace=self.root)
        path.write_bytes(original)
        self.manifest.write_bytes(self.manifest.read_bytes() + b'\n')
        with self.assertRaisesRegex(ValueError, 'approved review manifest changed'):
            approval.validate(receipt, workspace=self.root)

    def test_partial_and_duplicate_id_receipts_are_rejected(self):
        receipt = self.receipt()
        for identifiers in ([], ['fictional.first'], ['fictional.first', 'fictional.first']):
            changed = deepcopy(receipt)
            changed['approved_ids'] = identifiers
            with self.subTest(ids=identifiers), self.assertRaisesRegex(ValueError, 'every exact translation ID'):
                approval.validate(changed, workspace=self.root)

    def test_missing_human_attribution_pending_issues_and_wrong_scope_are_rejected(self):
        receipt = self.receipt()
        for key, value in (('reviewer', ''), ('statement', ' '), ('approved_at', '2026-01-01'),
                           ('open_issues', ['unresolved clue']), ('scope', 'some_translations'), ('status', 'draft'),
                           ('catalog_sha256', '0' * 64), ('bundle_sha256', '0' * 64)):
            changed = deepcopy(receipt)
            changed[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                approval.validate(changed, workspace=self.root)

    def test_all_public_real_translation_entry_points_check_approval_first(self):
        with patch('korean.production.require', side_effect=ValueError('human gate')), \
                patch('korean.capacity.symbols') as symbols:
            with self.assertRaisesRegex(ValueError, 'human gate'):
                production.build()
            symbols.assert_not_called()
        with patch('korean.approval.require', side_effect=ValueError('human gate')), \
                patch('korean.game_text.original_inputs') as inputs:
            with self.assertRaisesRegex(ValueError, 'human gate'):
                game_text.build(approved=True)
            inputs.assert_not_called()
        with patch('korean.approval.require', side_effect=ValueError('human gate')), \
                patch('korean.synthetic.build_text') as compiler:
            with self.assertRaisesRegex(ValueError, 'human gate'):
                synthetic.build(approved=True)
            compiler.assert_not_called()
        with patch('korean.image_check.require', side_effect=ValueError('human gate')), \
                patch('korean.image_check.read_json') as read_manifest:
            with self.assertRaisesRegex(ValueError, 'human gate'):
                image_check.verify()
            read_manifest.assert_not_called()

    def test_clock_mode_selects_literal_or_permuted_fictional_cells(self):
        encoding = GameEncoding('가나다라')
        entries = {'bitmap.d.am': {'translation': '가나'}, 'bitmap.d.pm': {'translation': '다라'}}
        literal, real = compile_clock(encoding, entries, synthetic=False)
        permuted, fake = compile_clock(encoding, entries)
        self.assertEqual([row['approved_text'] for row in real['replacements']], ['가나', '다라'])
        self.assertEqual([row['synthetic_text'] for row in fake['replacements']], ['나다', '라가'])
        self.assertEqual(len(literal), len(permuted))
        self.assertNotEqual(literal, permuted)


if __name__ == '__main__':
    unittest.main()
