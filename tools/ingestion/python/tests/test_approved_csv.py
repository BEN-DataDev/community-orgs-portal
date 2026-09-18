import copy
import csv
import hashlib
import io
import json
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest

from ingestion.approved_csv import extract, COLUMNS, MAX_BYTES
from ingestion.staging_sql import render

FIXTURE = Path(__file__).parent / 'fixtures/csv-pilot-v1'


class ApprovedCSVTests(unittest.TestCase):
    def setUp(self):
        self.data = (FIXTURE / 'organisations.csv').read_bytes()
        self.manifest = json.loads((FIXTURE / 'manifest.json').read_text())

    def changed(self, rows):
        out = io.StringIO(newline='')
        writer = csv.writer(out)
        writer.writerow(COLUMNS)
        writer.writerows(rows)
        data = out.getvalue().encode()
        m = copy.deepcopy(self.manifest)
        m['files']['organisations.csv'] = hashlib.sha256(data).hexdigest()
        m['row_count'] = len(rows)
        return data, m

    def rows(self):
        return list(csv.reader(io.StringIO(self.data.decode())))[1:]

    def test_qualified_fixture(self):
        e = extract(self.data, self.manifest)
        self.assertEqual(e['counts']['accepted'], 6)
        self.assertEqual(e['counts']['quarantined'], 3)
        self.assertEqual([r['disposition'] for r in e['records']], ['candidate', 'candidate', 'hold', 'hold', 'hold', 'hold'])
        self.assertEqual(e['records'][-1]['raw']['postcode'], '0800')
        self.assertEqual(e['records'][1]['raw']['incorporation_number'], '0000123')
        self.assertEqual(e['completion'], 'partial')
        self.assertEqual(e, extract(self.data, self.manifest))
        self.assertIn('ingestion.stage_csv(', render(e))
        self.assertNotIn('Synthetic Valley', render(e))

    def test_live_requires_approval(self):
        data, m = self.changed(self.rows()[:2])
        m['synthetic'] = False
        with self.assertRaises(ValueError):
            extract(data, m)
        m.update(access_status='approved', approved_by='Test operator',
                 approved_at='2026-09-17T00:00:00Z', access_evidence_ref='test:permission')
        e = extract(data, m)
        self.assertEqual(e['completion'], 'complete')
        self.assertFalse(e['publication_eligible'])
        self.assertNotEqual(e['run_id'], extract(data, {**m, 'observed_at': '2026-09-18T00:00:00Z'})['run_id'])

    def test_metadata_fails_closed(self):
        for key in ['source_id', 'publisher', 'licence', 'scope', 'files', 'row_count', 'observed_at', 'synthetic', 'attribution']:
            m = copy.deepcopy(self.manifest)
            del m[key]
            with self.subTest(key=key), self.assertRaises(ValueError):
                extract(self.data, m)
        with self.assertRaises(ValueError):
            extract(self.data + b'\n', self.manifest)
        with self.assertRaises(ValueError):
            extract(self.data, {**self.manifest, 'row_count': 8})

    def test_cli_exit_codes_and_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, manifest = root / 'organisations.csv', root / 'manifest.json'
            output, sql = root / 'envelope.json', root / 'stage.sql'
            source.write_bytes(self.data)
            manifest.write_text(json.dumps(self.manifest))
            command = [sys.executable, '-m', 'ingestion.approved_csv', '--input', str(source),
                       '--manifest', str(manifest), '--output', str(output), '--sql-output', str(sql)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertEqual(json.loads(output.read_text())['counts']['quarantined'], 3)
            self.assertIn('SET LOCAL ROLE ingestion_worker', sql.read_text())
            output.unlink()
            sql.unlink()
            source.write_bytes(b'wrong content')
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertFalse(output.exists())
            self.assertFalse(sql.exists())

    def test_file_structure(self):
        for data in [b'\xff', b'a,a\n1,2\n', (','.join(COLUMNS)+'\n"unclosed').encode(),
                     (','.join(COLUMNS)+'\na,b\n').encode()]:
            m = copy.deepcopy(self.manifest)
            m['files']['organisations.csv'] = hashlib.sha256(data).hexdigest()
            with self.subTest(data=data), self.assertRaises(ValueError):
                extract(data, m)
        with self.assertRaises(ValueError):
            extract(b'x' * (MAX_BYTES + 1), self.manifest)

    def test_duplicate_ids_quarantine_all_occurrences(self):
        rows = self.rows()[:2]
        rows[1][0] = rows[0][0]
        e = extract(*self.changed(rows))
        self.assertEqual(len(e['records']), 0)
        self.assertEqual(len(e['quarantine']), 2)

    def test_invalid_rows(self):
        cases = {'website': ['ftp://example.org', 'https://user@example.org', 'https://x:bad', 'https://[bad'],
                 'abn': ['１２３４５６７８９０１'], 'postcode': ['123'], 'state': ['ZZ'],
                 'source_modified_at': ['2026-02-30T00:00:00Z', '2026-09-18'],
                 'incorporation_number': ['00001'], 'entity_kind': ['company'], 'scope_basis': ['everywhere']}
        for key, values in cases.items():
            for value in values:
                rows = self.rows()[:1]
                rows[0][COLUMNS.index(key)] = value
                with self.subTest(key=key, value=value):
                    e = extract(*self.changed(rows))
                    self.assertEqual(len(e['quarantine']), 1)

    def test_unicode_multiline_bom_and_omissions(self):
        rows = self.rows()[:1]
        rows[0][COLUMNS.index('description')] = 'Café, gardens\nand people'
        data, m = self.changed(rows)
        data = b'\xef\xbb\xbf' + data
        m['files']['organisations.csv'] = hashlib.sha256(data).hexdigest()
        e = extract(data, m)
        self.assertIn('\n', e['records'][0]['raw']['description'])
        self.assertNotIn('website', [a['field'] for a in e['records'][0]['assertions']])
        self.assertEqual(e['completion'], 'partial')  # Synthetic clean files cannot publish.


if __name__ == '__main__':
    unittest.main()
