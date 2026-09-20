import csv
import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from urllib.error import HTTPError

from ingestion.acquisition_output import manifest, write_outputs
from ingestion.adapters.acnc import digest
from ingestion.bulk_acnc import (BulkTransport, acquire_bulk, bulk_configuration, extract)
from ingestion.live_acnc import TEXT_FIELDS
from ingestion.staging_sql import render, validate
from test_live_acnc import CONFIG

STAMP = '2026-09-18T00:00:00Z'
BULK_CONFIG = {**CONFIG, 'resource_id': '00000000-0000-4000-8000-000000000013',
               'identity_column': 'ABN', 'max_bulk_bytes': 1024 * 1024,
               'max_bulk_rows': 1000}
BULK_CONFIG['bulk_url'] = ('https://data.gov.au/data/dataset/acnc-register/resource/'
                           + BULK_CONFIG['resource_id'] + '/download/register.csv')
ROW = json.loads(Path('tests/fixtures/acnc-field-coverage.json').read_text())['populated']
ROW = {key: value for key, value in ROW.items() if key != '_id'}
ROW['Postcode'] = '2730'


def csv_bytes(rows=None, headers=None):
    stream = io.StringIO(newline='')
    writer = csv.DictWriter(stream, fieldnames=headers or sorted(TEXT_FIELDS))
    writer.writeheader()
    writer.writerows([ROW] if rows is None else rows)
    return stream.getvalue().encode('utf-8')


class BulkReader:
    def __init__(self, data=None, changed=False):
        self.data = csv_bytes() if data is None else data
        self.requests = 0
        self.changed = changed
        self.end = 100
        self.clock = lambda: 0

    def get(self, action, params):
        self.requests += 1
        return {'success': True, 'result': {'name': 'acnc-register', 'id': 'dataset',
            'license_title': CONFIG['expected_licence_title'],
            'metadata_modified': 'two' if self.changed and self.requests > 1 else 'one',
            'resources': [{'id': BULK_CONFIG['resource_id'], 'datastore_active': False,
                           'url': BULK_CONFIG['bulk_url'], 'format': 'CSV'}]}}

    def download(self, url, output, max_bytes):
        self.requests += 1
        output.write(self.data)


class BulkTests(unittest.TestCase):
    def acquire(self, reader=None, config=None):
        return acquire_bulk(config or BULK_CONFIG, reader or BulkReader(), 'bulk-fixture', STAMP)

    def test_complete_mapping_provenance_and_staging(self):
        result = self.acquire()
        validate(result)
        self.assertEqual(result['completion'], 'complete')
        record = result['records'][0]
        self.assertEqual(record['native_id'], 'abn:00000000000')
        self.assertNotIn('_id', record['raw'])
        self.assertEqual(record['raw'], ROW)
        self.assertEqual(len(record['assertions']), 62)
        self.assertEqual(result['qualification']['file_sha256'], hashlib.sha256(csv_bytes()).hexdigest())
        self.assertFalse(result['publication_eligible'])
        self.assertIn('ingestion.stage_acnc', render(result))
        self.assertEqual(manifest(result)['envelope_sha256'], digest(result))
        self.assertEqual(result, self.acquire())

    def test_filtered_scan_and_empty_are_complete_only_at_eof(self):
        outside = {**ROW, 'ABN': '11111111111', 'Postcode': '0800'}
        result = self.acquire(BulkReader(csv_bytes([outside, ROW])))
        self.assertEqual(result['counts']['accepted'], 1)
        self.assertEqual(result['scope']['filters']['Postcode'], CONFIG['postcodes'])
        self.assertFalse(result['scope']['complete_snapshot'])
        self.assertEqual(result['bulk_scan']['rows_scanned'], 2)
        result = self.acquire(BulkReader(csv_bytes([outside])))
        self.assertEqual(result['completion'], 'complete')
        self.assertEqual(result['counts']['source_total'], 0)
        self.assertTrue(result['bulk_scan']['reached_eof'])
        self.assertEqual(self.acquire(BulkReader(csv_bytes([])))['completion'], 'complete')
        self.assertEqual(self.acquire(BulkReader(b''))['completion'], 'failed')

    def test_bom_unicode_quotes_and_multiline(self):
        row = {**ROW, 'Charity_Legal_Name': 'Synthetic café, "arts"\ncommunity'}
        result = self.acquire(BulkReader(b'\xef\xbb\xbf' + csv_bytes([row])))
        self.assertEqual(result['completion'], 'complete')
        self.assertEqual(result['records'][0]['raw']['Charity_Legal_Name'], row['Charity_Legal_Name'])

    def test_selects_every_configured_postcode(self):
        rows = [ROW, {**ROW, 'ABN': '11111111111', 'Postcode': '2720'}]
        result = self.acquire(BulkReader(csv_bytes(rows)))
        self.assertEqual(result['completion'], 'complete')
        self.assertEqual(result['counts']['accepted'], 2)

    def test_schema_and_encoding_fail_closed(self):
        good = csv_bytes()
        for data in [good.replace(b'ABN,', b'Unknown,'), good.replace(b'ABN,', b'ABN,ABN,'),
                     good + b'"unclosed', b'\xff' + good, good + b'a,b\n',
                     good.replace(b'Synthetic Field', b'Synthetic\x00Field')]:
            with self.subTest(data=data[:20]):
                result = self.acquire(BulkReader(data))
                self.assertNotEqual(result['completion'], 'complete')
                self.assertTrue(result['errors'])

    def test_duplicate_missing_and_invalid_identity(self):
        for rows in [[ROW, ROW], [{**ROW, 'ABN': ''}], [{**ROW, 'ABN': 'bad'}],
                     [ROW, {**ROW, 'Postcode': '0800'}]]:
            with self.subTest(rows=len(rows)):
                self.assertNotEqual(self.acquire(BulkReader(csv_bytes(rows)))['completion'], 'complete')

    def test_missing_identity_outside_scope_does_not_invent_a_record(self):
        result = self.acquire(BulkReader(csv_bytes([{**ROW, 'ABN': '', 'Postcode': ''}, ROW])))
        self.assertEqual(result['completion'], 'complete')
        self.assertEqual(result['counts']['accepted'], 1)
        self.assertEqual(result['bulk_scan']['outside_scope_identity_issues'], 1)
        self.assertEqual(len(result['records']), 1)
        # An out-of-scope record still prevents a selected duplicate ABN from
        # being treated as a unique source identity, in either file order.
        outside = {**ROW, 'Postcode': '0800'}
        for rows in [[outside, ROW], [ROW, outside]]:
            self.assertEqual(self.acquire(BulkReader(csv_bytes(rows)))['completion'], 'partial')

    def test_ckan_identity_does_not_fabricate_abn(self):
        row = {**ROW, '_id': '123', 'ABN': ''}
        config = {**BULK_CONFIG, 'identity_column': '_id'}
        result = self.acquire(BulkReader(csv_bytes([row], ['_id'] + sorted(TEXT_FIELDS))), config)
        self.assertEqual(result['completion'], 'complete')
        self.assertEqual(result['records'][0]['native_id'], '123')
        self.assertEqual(result['records'][0]['raw']['_id'], '123')

    def test_quarantine_preserves_raw_and_blocks_completion(self):
        row = {**ROW, 'Operates_in_ACT': 'maybe'}
        result = self.acquire(BulkReader(csv_bytes([row])))
        self.assertEqual(result['completion'], 'partial')
        self.assertEqual(result['records'], [])
        self.assertEqual(result['quarantine'][0]['raw'], row)

    def test_row_selected_byte_and_time_limits(self):
        rows = [ROW, {**ROW, 'ABN': '11111111111'}]
        for config in [{**BULK_CONFIG, 'max_bulk_rows': 1},
                       {**BULK_CONFIG, 'page_size': 1, 'max_pages': 1},
                       {**BULK_CONFIG, 'max_bulk_bytes': 1024}]:
            result = self.acquire(BulkReader(csv_bytes(rows)), config)
            self.assertNotEqual(result['completion'], 'complete')
        reader = BulkReader()
        reader.clock = lambda: 101
        self.assertNotEqual(self.acquire(reader)['completion'], 'complete')

    def test_metadata_drift_licence_resource_and_url(self):
        self.assertEqual(self.acquire(BulkReader(changed=True))['completion'], 'partial')
        for key, value in [('bulk_url', BULK_CONFIG['bulk_url'] + '.other'),
                           ('resource_id', CONFIG['resource_id']),
                           ('expected_licence_title', 'different')]:
            self.assertEqual(self.acquire(config={**BULK_CONFIG, key: value})['completion'], 'failed')

    def test_configuration_rejects_unbounded_and_arbitrary_urls(self):
        self.assertEqual(bulk_configuration(BULK_CONFIG), BULK_CONFIG)
        for key, value in [('max_bulk_rows', 100001), ('max_bulk_bytes', True),
                           ('identity_column', 'row_number'),
                           ('bulk_url', 'https://example.org/register.csv'),
                           ('bulk_url', BULK_CONFIG['bulk_url'] + '?redirect=1'),
                           ('bulk_url', BULK_CONFIG['bulk_url'].replace('https:', 'http:'))]:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                bulk_configuration({**BULK_CONFIG, key: value})

    def test_transport_download_limits_and_http_errors(self):
        class Opener:
            def open(self, request, **kwargs):
                return io.BytesIO(b'x' * 1025)
        transport = BulkTransport(BULK_CONFIG, opener=Opener())
        with self.assertRaisesRegex(ValueError, 'byte limit'):
            transport.download(BULK_CONFIG['bulk_url'], io.BytesIO(), 1024)
        class Missing:
            def open(self, request, **kwargs):
                raise HTTPError(request.full_url, 503, 'down', {}, None)
        transport = BulkTransport(BULK_CONFIG, opener=Missing())
        with self.assertRaisesRegex(ValueError, 'Bulk HTTP 503'):
            transport.download(BULK_CONFIG['bulk_url'], io.BytesIO(), 1024)
        self.assertEqual(transport.requests, 1)
        transport = BulkTransport(BULK_CONFIG, opener=Opener(), clock=lambda: 0)
        transport.end = 0
        with self.assertRaisesRegex(ValueError, 'budget exhausted'):
            transport.download(BULK_CONFIG['bulk_url'], io.BytesIO(), 1024)

    def test_private_outputs_are_not_overwritten(self):
        result = self.acquire()
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            write_outputs(directory, result)
            for filename in ['envelope.json', 'manifest.json']:
                self.assertEqual((directory / filename).stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                write_outputs(directory, result)

    def test_truncated_or_compressed_transfer_is_not_complete_csv(self):
        class Opener:
            def __init__(self, headers):
                self.headers = headers
            def open(self, *args, **kwargs):
                response = io.BytesIO(b'header\n')
                response.headers = self.headers
                return response
        for headers in [{'Content-Length': '100'}, {'Content-Length': '9999999'},
                        {'Content-Length': 'not-a-number'}, {'Content-Encoding': 'gzip'}]:
            with self.subTest(headers=headers), self.assertRaises(ValueError):
                BulkTransport(BULK_CONFIG, opener=Opener(headers)).download(
                    BULK_CONFIG['bulk_url'], io.BytesIO(), 1024)


if __name__ == '__main__':
    unittest.main()
