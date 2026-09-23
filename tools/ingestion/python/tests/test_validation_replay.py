import copy
import unittest

from ingestion.adapters.acnc import ACNCExtractor, digest
from ingestion.validation_issues import evidence_hash
from ingestion.validation_replay import replay
from ingestion.approved_csv import COLUMNS


RAW = {'_id': '7', 'Charity_Legal_Name': 'Validation fixture',
       'Charity_Website': 'example.org/path'}


def parent():
    return {
        'contract_version': '1.0', 'source_id': 'acnc-register', 'resource_id': 'fixture',
        'run_id': 'parent', 'parser_version': 'acnc-ckan-v3',
        'observed_at': '2026-09-23T00:00:00Z', 'completion': 'partial',
        'publication_eligible': False, 'scope': {'complete_snapshot': False},
        'pages': [], 'errors': [], 'records': [],
        'quarantine': [{'row': 0, 'native_id': '7', 'raw': copy.deepcopy(RAW),
                        'raw_sha256': digest(RAW), 'reason': 'Charity_Website: invalid'}],
        'issues': [], 'counts': {'accepted': 0, 'quarantined': 1, 'pages': 0, 'source_total': 1},
    }


def request(decision='correct', source_hash=None):
    return {
        'id': '00000000-0000-4000-8000-000000000341', 'parent_run_id': 30,
        'parent_envelope_sha256': digest(parent()), 'envelope': parent(),
        'resolutions': [{
            'issue_id': '1', 'revision': 1, 'decision': decision, 'native_id': '7', 'row': 0,
            'source_key': 'Charity_Website', 'canonical_key': 'website',
            'source_value': RAW['Charity_Website'],
            'raw_evidence_hash': source_hash or evidence_hash(RAW['Charity_Website']),
            'proposed_value': 'https://example.org/path',
            'canonical_value': 'https://example.org/path',
            'validator_name': 'http_url', 'validator_version': 'acnc-ckan-v3',
        }],
    }


class ValidationReplayTests(unittest.TestCase):
    def test_acnc_correction_revalidates_every_record_into_separate_run(self):
        result = replay(request())
        self.assertEqual(result['completion'], 'complete')
        self.assertEqual(result['quarantine'], [])
        self.assertEqual(result['errors'], [])
        self.assertFalse(result['publication_eligible'])
        self.assertEqual(result['observed_at'], parent()['observed_at'])
        self.assertEqual(result['scope'], parent()['scope'])
        self.assertEqual(result['records'][0]['raw']['Charity_Website'], 'https://example.org/path')
        website = next(x for x in result['records'][0]['assertions'] if x['field'] == 'website')
        self.assertEqual(website['value'], 'https://example.org/path')
        self.assertEqual(result['validation_replay']['parent_run_id'], 30)

    def test_changed_evidence_and_deferred_decisions_fail_closed(self):
        with self.assertRaisesRegex(ValueError, 'evidence changed'):
            replay(request(source_hash='0' * 64))
        with self.assertRaisesRegex(ValueError, 'unresolved'):
            replay(request(decision='defer'))

    def test_reject_record_cannot_claim_complete(self):
        result = replay(request(decision='reject_record'))
        self.assertEqual(result['completion'], 'partial')
        self.assertEqual(len(result['quarantine']), 1)

    def test_adapter_emits_field_addressable_issue(self):
        payload = {'success': True, 'result': {'total': 1, 'records': [RAW]}}
        envelope = ACNCExtractor(lambda _: payload, 'fixture').extract(
            filters={'Postcode': '2730'}, run_id='issues', observed_at='2026-09-23T00:00:00Z')
        self.assertEqual(envelope['completion'], 'partial')
        self.assertEqual(envelope['issues'][0]['field'], {
            'source_key': 'Charity_Website', 'canonical_key': 'website'})
        self.assertEqual(envelope['issues'][0]['allowed_resolutions'],
                         ['correct', 'omit', 'defer', 'reject_record'])
        self.assertEqual(envelope['quarantine'][0]['issues'], envelope['issues'])

    def test_approved_csv_uses_the_same_replay_boundary(self):
        raw = {key: '' for key in COLUMNS}
        raw.update(source_record_id='csv-1', entity_name='CSV fixture', entity_kind='legal_entity',
                   website='example.org/path', scope_basis='located_in', evidence_ref='test:evidence')
        envelope = {
            'contract_version': '1.0', 'source_id': 'approved-provider', 'resource_id': 'fixture',
            'run_id': 'csv-parent', 'parser_version': 'approved-csv-v1',
            'observed_at': '2026-09-23T00:00:00Z', 'completion': 'partial',
            'publication_eligible': False, 'scope': {'complete_snapshot': False},
            'qualification': {'approved': True}, 'pages': [], 'errors': [], 'records': [],
            'quarantine': [{'row': 1, 'native_id': 'csv-1', 'raw': raw,
                            'raw_sha256': digest(raw), 'reason': 'website invalid'}],
            'issues': [], 'counts': {'accepted': 0, 'quarantined': 1, 'pages': 0, 'source_total': 1},
        }
        job = {
            'id': '00000000-0000-4000-8000-000000000342', 'parent_run_id': 31,
            'parent_envelope_sha256': digest(envelope), 'envelope': envelope,
            'resolutions': [{
                'issue_id': '2', 'revision': 1, 'decision': 'correct', 'native_id': 'csv-1',
                'row': 1, 'source_key': 'website', 'canonical_key': 'website',
                'source_value': raw['website'], 'raw_evidence_hash': evidence_hash(raw['website']),
                'proposed_value': 'https://example.org/path',
                'canonical_value': 'https://example.org/path',
                'validator_name': 'approved_csv_field', 'validator_version': 'approved-csv-v1',
            }],
        }
        result = replay(job)
        self.assertEqual(result['completion'], 'complete')
        self.assertEqual(result['records'][0]['native_id'], 'csv-1')
        self.assertEqual(next(x for x in result['records'][0]['assertions']
                              if x['field'] == 'website')['value'], 'https://example.org/path')


if __name__ == '__main__':
    unittest.main()
