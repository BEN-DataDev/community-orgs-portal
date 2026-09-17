import copy
import unittest

from ingestion.adapters.acnc import ACNCExtractor, digest, PARSER_VERSION
from ingestion.field_coverage import load, PACKAGE
from ingestion.reprocess_acnc import reprocess, coverage


def original():
    row = load(PACKAGE / 'tests/fixtures/acnc-field-coverage.json')['populated']
    result = ACNCExtractor(lambda _: {'success': True, 'result': {'total': 1, 'records': [row]}},
                           'f05-synthetic').extract(filters={'State': 'NT'}, run_id='f05-original',
                                                    observed_at='2026-09-16T00:00:00Z')
    result['synthetic'] = True
    result['parser_version'] = 'acnc-ckan-v1'
    for record in result['records']:
        record['parser_version'] = 'acnc-ckan-v1'
        record.pop('mapping_version')
        record['assertions'] = [a for a in record['assertions'] if a['field'] in ('entity_name', 'abn', 'website')]
    return result


def replay(e):
    return reprocess(e, parent_run_id=1, run_id='f05-replay', processed_at='2026-09-17T00:00:00Z')


class ReprocessTests(unittest.TestCase):
    def test_replay_preserves_evidence_and_is_deterministic(self):
        old = original()
        snapshot = copy.deepcopy(old)
        new = replay(old)
        self.assertEqual(old, snapshot)
        self.assertEqual(new, replay(old))
        self.assertEqual(new['observed_at'], old['observed_at'])
        self.assertEqual(new['pages'], old['pages'])
        self.assertEqual(new['records'][0]['raw_sha256'], old['records'][0]['raw_sha256'])
        self.assertEqual(new['records'][0]['raw'], old['records'][0]['raw'])
        self.assertEqual(len(new['records'][0]['assertions']), 62)
        self.assertFalse(new['publication_eligible'])
        self.assertEqual(new['reprocessing']['parent_envelope_sha256'], digest(old))

    def test_rejects_tampered_evidence_identity_and_non_acquisition(self):
        mutations = [lambda e: e['records'][0]['raw'].update(ABN='12345678901'),
                     lambda e: e['records'][0].update(native_id='different'),
                     lambda e: e.update(completion='partial'),
                     lambda e: e.update(parser_version=PARSER_VERSION)]
        for mutate in mutations:
            with self.subTest(mutate=mutate), self.assertRaises(ValueError):
                e = original()
                mutate(e)
                replay(e)

    def test_quarantine_accounts_for_all_fields_without_inventing_success(self):
        e = original()
        r = e['records'][0]
        r['raw'].update(Charity_Website='bad website', PBI=None, Future_Column='unmapped')
        r['raw_sha256'] = digest(r['raw'])
        new = replay(e)
        self.assertEqual(new['completion'], 'partial')
        self.assertEqual(new['records'], [])
        self.assertEqual(new['quarantine'][0]['raw_sha256'], r['raw_sha256'])
        report = coverage(new)
        self.assertEqual(report['source_counts'], {'supplied': 67, 'absent': 1, 'invalid': 1, 'unmapped': 1})
        self.assertFalse(report['workflow_verified'])
        self.assertTrue(all(f['approved'] is None for f in report['records'][0]['fields']))

    def test_absence_false_and_workflow_states_are_independent(self):
        e = original()
        r = e['records'][0]
        r['raw'].update(PBI='N', HPC='')
        r['raw_sha256'] = digest(r['raw'])
        new = replay(e)
        workflow = {'run_key': new['run_id'], 'source_id':new['source_id'], 'resource_id':new['resource_id'],
                    'records': [{'native_id': r['native_id'], 'fields': [
            {'field': 'pbi', 'status': 'suppressed', 'approved': True, 'published': True,
             'previously_published': True, 'suppressed': True}]}]}
        fields = {f['source_key']: f for f in coverage(new, workflow)['records'][0]['fields']}
        self.assertEqual(fields['PBI']['source_status'], 'supplied')
        self.assertTrue(fields['PBI']['suppressed'])
        self.assertEqual(fields['HPC']['source_status'], 'absent')
        workflow['resource_id'] = 'different-resource'
        with self.assertRaises(ValueError):
            coverage(new, workflow)
