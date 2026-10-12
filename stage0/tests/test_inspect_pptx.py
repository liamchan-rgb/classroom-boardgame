"""Meaningful format-boundary tests for the stage0 parser; fixtures are generated locally."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile, ZIP_DEFLATED

tool_path = Path(__file__).parents[1] / 'tools' / 'inspect_pptx.py'
spec = importlib.util.spec_from_file_location('inspect_pptx', tool_path)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

P = 'http://schemas.openxmlformats.org/presentationml/2006/main'
A = 'http://schemas.openxmlformats.org/drawingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'


def fixture(path, *, missing_slide=False, broken_notes=False, unsafe_target=False):
    # Actual order is slide9, slide2. Notes filename intentionally does not match slide index.
    target = '../../outside.xml' if unsafe_target else 'slides/slide9.xml'
    parts = {
        'ppt/presentation.xml': f'<p:presentation xmlns:p="{P}" xmlns:r="{R}"><p:sldIdLst><p:sldId id="256" r:id="rIdA"/><p:sldId id="257" r:id="rIdB"/></p:sldIdLst><p:sldSz cx="12192000" cy="6858000"/></p:presentation>',
        'ppt/_rels/presentation.xml.rels': f'<Relationships><Relationship Id="rIdA" Type="{R}/slide" Target="{target}"/><Relationship Id="rIdB" Type="{R}/slide" Target="slides/slide2.xml"/></Relationships>',
        'ppt/slides/slide9.xml': f'<p:sld xmlns:p="{P}" xmlns:a="{A}"><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>First public page</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:sld>',
        'ppt/slides/slide2.xml': f'<p:sld xmlns:p="{P}" xmlns:a="{A}"><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>Second public page</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:sld>',
        'ppt/slides/_rels/slide9.xml.rels': f'<Relationships><Relationship Id="notes" Type="{R}/notesSlide" Target="../notesSlides/notesSlide42.xml"/><Relationship Id="web" Type="{R}/hyperlink" Target="https://example.invalid/never-fetch" TargetMode="External"/></Relationships>',
        'ppt/notesSlides/notesSlide42.xml': f'<p:notes xmlns:p="{P}" xmlns:a="{A}"><p:sp><p:nvSpPr><p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>PRIVATE_MARKER 教师台词</a:t></a:r><a:br/><a:r><a:t>{"长备注" * 1000}</a:t></a:r></a:p></p:txBody></p:sp><p:sp><p:nvSpPr><p:nvPr><p:ph type="sldNum"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>FOOTER_NUMBER</a:t></a:r></a:p></p:txBody></p:sp></p:notes>'
    }
    if missing_slide:
        parts.pop('ppt/slides/slide9.xml')
    if broken_notes:
        parts['ppt/notesSlides/notesSlide42.xml'] = '<broken'
    with ZipFile(path, 'w', ZIP_DEFLATED) as archive:
        for name, value in parts.items():
            archive.writestr(name, value)


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.deck = self.root / 'fixture.pptx'

    def tearDown(self):
        self.directory.cleanup()

    def test_actual_order_notes_relationship_empty_long_and_footer(self):
        fixture(self.deck)
        private, public, report = tool.inspect(self.deck)
        self.assertEqual([p['texts'] for p in private['pages']],
                         ['First public page', 'Second public page'])
        self.assertIn('PRIVATE_MARKER', private['pages'][0]['notes'])
        self.assertNotIn('FOOTER_NUMBER', private['pages'][0]['notes'])
        self.assertGreater(len(private['pages'][0]['notes']), 3000)
        self.assertEqual(private['pages'][1]['notes'], '')
        self.assertNotIn('PRIVATE_MARKER', json.dumps(public))
        self.assertNotIn('PRIVATE_MARKER', json.dumps(report))
        self.assertEqual(report['pages'][0]['external_relationships'], 1)
        self.assertEqual(report['AC35'], 'not_passed')

    def test_missing_page_is_reported_in_place_not_silently_dropped(self):
        fixture(self.deck, missing_slide=True)
        _, _, report = tool.inspect(self.deck)
        self.assertEqual(report['page_count'], 2)
        self.assertEqual(report['pages'][0]['structure_status'], 'failed')
        self.assertEqual(report['pages'][1]['structure_status'], 'parsed')

    def test_inspection_works_when_network_access_is_blocked(self):
        fixture(self.deck)
        with patch('socket.socket', side_effect=AssertionError('Network is forbidden')):
            private, public, report = tool.inspect(self.deck)
        self.assertEqual(len(private['pages']), 2)
        self.assertEqual(len(public['pages']), 2)
        self.assertEqual(report['network_requests'], 0)

    def test_broken_notes_is_failure_not_empty_success(self):
        fixture(self.deck, broken_notes=True)
        _, _, report = tool.inspect(self.deck)
        self.assertEqual(report['pages'][0]['structure_status'], 'failed')
        self.assertIn('XML', report['pages'][0]['issues'][0])

    def test_invalid_package_leaves_existing_output_unchanged(self):
        self.deck.write_bytes(b'not a zip')
        output = self.root / 'existing'
        output.mkdir()
        marker = output / 'keep.txt'
        marker.write_text('keep')
        with self.assertRaises(tool.InvalidDeck):
            tool.write_results(self.deck, output)
        self.assertEqual(marker.read_text(), 'keep')
        self.assertEqual(list(output.iterdir()), [marker])

    def test_existing_evidence_is_not_overwritten(self):
        fixture(self.deck)
        output = self.root / 'output'
        tool.write_results(self.deck, output)
        before = (output / 'import-report.json').read_bytes()
        with self.assertRaises(tool.InvalidDeck):
            tool.write_results(self.deck, output)
        self.assertEqual((output / 'import-report.json').read_bytes(), before)

    def test_unsafe_relationship_is_rejected(self):
        fixture(self.deck, unsafe_target=True)
        with self.assertRaises(tool.InvalidDeck):
            tool.inspect(self.deck)

    def test_dtd_is_rejected(self):
        with ZipFile(self.deck, 'w') as archive:
            archive.writestr('ppt/presentation.xml', '<!DOCTYPE x [<!ENTITY y "test">]><x/>')
        with self.assertRaises(tool.InvalidDeck):
            tool.inspect(self.deck)


if __name__ == '__main__':
    unittest.main(verbosity=2)
