import copy
import io
import json
import unittest
from pathlib import Path
from urllib.error import HTTPError
from ingestion.live_acnc import configuration, Transport, acquire, TEXT_FIELDS
CONFIG = json.loads(Path('config/acnc-pilot.json').read_text())
FIXTURE = json.loads(Path('tests/fixtures/acnc-pages.json').read_text())
class Reader:
    requests = 0
    def __init__(self, changed=False, malformed=False):
        self.changed, self.malformed = changed, malformed
    def get(self, action, params):
        self.requests += 1
        if action == 'package_show':
            return {'success': True, 'result': {'name': 'acnc-register', 'id': 'dataset',
                'license_title': CONFIG['expected_licence_title'],
                'metadata_modified': 'two' if self.changed and self.requests > 1 else 'one',
                'resources': [{'id': CONFIG['resource_id'], 'datastore_active': True}]}}
        result = copy.deepcopy(FIXTURE['pages'][str(params['offset'])])
        result['result']['fields'] = [{'id': '_id', 'type': 'int'}] + [
            {'id': key, 'type': 'text'} for key in TEXT_FIELDS]
        if self.malformed:
            result['result']['fields'][0] = {}
        return result
class LiveTests(unittest.TestCase):
    def test_limits_and_scope(self):
        self.assertEqual(configuration(CONFIG)['postcode'], '2730')
        for key, value in [('postcode', 'NSW'), ('max_pages', 11), ('page_size', 0),
                           ('timeout_seconds', 100), ('max_response_bytes', 999999999)]:
            with self.assertRaises(ValueError): configuration({**CONFIG, key: value})
    def run_extract(self, reader):
        return acquire({**CONFIG, 'page_size': 5}, reader, 'live-fixture', '2026-09-16T00:00:00Z')
    def test_complete_and_metadata_drift(self):
        result = self.run_extract(Reader())
        self.assertEqual(result['completion'], 'complete')
        self.assertFalse(result['publication_eligible'])
        self.assertFalse(result['qualification']['snapshot_guaranteed'])
        self.assertEqual(self.run_extract(Reader(changed=True))['completion'], 'partial')
    def test_schema_fails_closed(self):
        result = self.run_extract(Reader(malformed=True))
        self.assertEqual(result['completion'], 'failed')
        self.assertEqual(result['records'], [])
    def test_retry_and_byte_limit(self):
        class Opener:
            count = 0
            def open(self, request, timeout):
                self.count += 1
                if self.count < 3: raise HTTPError(request.full_url, 503, 'unavailable', {}, None)
                return io.BytesIO(b'{"success":true}')
        opener = Opener()
        self.assertTrue(Transport(CONFIG, opener, sleep=lambda _: None).get('package_show', {})['success'])
        self.assertEqual(opener.count, 3)
        class Oversize:
            def open(self, *args, **kwargs): return io.BytesIO(b'x' * 1025)
        with self.assertRaisesRegex(ValueError, 'byte limit'):
            Transport({**CONFIG, 'max_response_bytes':1024}, Oversize()).get('package_show', {})
    def test_no_retry_for_404_and_expired_budget(self):
        class Missing:
            def open(self, request, **kwargs): raise HTTPError(request.full_url, 404, 'missing', {}, None)
        client = Transport(CONFIG, Missing())
        with self.assertRaisesRegex(ValueError, 'not retried'): client.get('package_show', {})
        self.assertEqual(client.requests, 1)
        times = iter([0, 1000])
        with self.assertRaisesRegex(ValueError, 'budget exhausted'):
            Transport(CONFIG, clock=lambda: next(times)).get('package_show', {})

    def test_retry_after_exceeds_budget(self):
        class Busy:
            def open(self, request, **kwargs):
                raise HTTPError(request.full_url, 429, 'busy', {'Retry-After': '300'}, None)
        with self.assertRaisesRegex(ValueError, 'retry deadline'):
            Transport(CONFIG, Busy()).get('package_show', {})

    def test_wrong_scope_is_not_accepted(self):
        class WrongScope(Reader):
            def get(self, action, params):
                result = super().get(action, params)
                if action == 'datastore_search':
                    result['result']['records'][0]['Postcode'] = '9999'
                return result
        result = self.run_extract(WrongScope())
        self.assertEqual(result['completion'], 'failed')
        self.assertEqual(result['records'], [])

    def test_licence_and_resource_changes_fail_closed(self):
        class ChangedLicence(Reader):
            def get(self, action, params):
                result = super().get(action, params)
                if action == 'package_show':
                    result['result']['license_title'] = 'Changed terms'
                return result
        class Inactive(Reader):
            def get(self, action, params):
                result = super().get(action, params)
                if action == 'package_show':
                    result['result']['resources'][0]['datastore_active'] = False
                return result
        for reader in [ChangedLicence(), Inactive()]:
            result = self.run_extract(reader)
            self.assertEqual(result['completion'], 'failed')
            self.assertEqual(result['records'], [])

    def test_redirects_refused(self):
        from ingestion.live_acnc import NoRedirect
        with self.assertRaisesRegex(ValueError, 'redirect refused'):
            NoRedirect().redirect_request(None, None, 302, '', {}, 'http://localhost')
