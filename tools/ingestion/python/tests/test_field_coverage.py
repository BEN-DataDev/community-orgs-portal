import copy
import unittest

from ingestion.field_coverage import EVIDENCE, MANIFEST, PACKAGE, REPORT, load, render, validate
from ingestion.adapters.acnc import normalise


class FieldCoverageTests(unittest.TestCase):
    def setUp(self):
        self.manifest = load(MANIFEST)
        self.schema = load(EVIDENCE)['qualification']['field_types']
        self.fixture = load(PACKAGE / 'tests/fixtures/acnc-field-coverage.json')

    def test_all_observed_columns_and_generated_report(self):
        self.assertEqual(validate(self.manifest, self.schema), [])
        self.assertEqual(len(self.manifest['fields']), 70)
        self.assertEqual(REPORT.read_text(), render(self.manifest))
        self.assertEqual(set(self.fixture['populated']), set(self.schema))
        for f in self.manifest['fields']:
            self.assertTrue(f['fixture_ref'].endswith('/' + f['source_key']))
            self.assertIsInstance(self.fixture['populated'][f['source_key']],
                                  int if f['source_type'] == 'int' else str)

    def test_future_columns_missing_columns_and_type_drift_fail(self):
        for change in ('new', 'missing', 'type'):
            schema = dict(self.schema)
            if change == 'new':
                schema['Future_Fact'] = 'text'
            elif change == 'missing':
                del schema['Charity_Website']
            else:
                schema['Postcode'] = 'int'
            self.assertTrue(validate(self.manifest, schema), change)

    def test_duplicate_or_undocumented_mappings_fail(self):
        manifest = copy.deepcopy(self.manifest)
        manifest['fields'].append(manifest['fields'][0])
        self.assertTrue(validate(manifest, self.schema))
        manifest = copy.deepcopy(self.manifest)
        manifest['fields'][1]['public']['route'] = None
        self.assertTrue(validate(manifest, self.schema))

    def test_only_technical_id_is_excluded_and_every_public_field_has_a_review_unit(self):
        excluded = [f['source_key'] for f in self.manifest['fields']
                    if f['public']['excluded_reason']]
        self.assertEqual(excluded, ['_id'])
        publishable = {f['canonical_key'] for f in self.manifest['fields']
                       if f['implementation_status'] == 'publishable'}
        self.assertEqual(len(publishable), 69)
        assertions = {a['field'] for a in normalise(self.fixture['populated'])['assertions']}
        self.assertEqual(assertions, {f['review_unit'] for f in self.manifest['fields']
                                     if f['implementation_status'] == 'publishable'})

    def test_database_allowlist_matches_mapping_contract(self):
        import json
        from ingestion.field_coverage import ROOT
        sql = (ROOT / 'supabase/migrations/20260916080000_complete_field_publication.sql').read_text()
        mappings = {m['field']: m for m in json.loads(sql.split('$mapping$')[1])}
        self.assertEqual(len(mappings), 62)
        for f in self.manifest['fields']:
            if f['source_key'] == '_id':
                continue
            actual = mappings[f['review_unit']]
            self.assertEqual(actual['table_name'], f['destination']['table'])
            self.assertEqual(actual['column_name'], f['destination']['column'])
            self.assertEqual(actual['mapping_version'], self.manifest['manifest_version'])
            if f['review_unit'] != 'administrative_address':
                self.assertEqual(actual['path'], f['destination']['json_path'])
                self.assertEqual(actual['kind'], f['canonical_type'])

    def test_lossy_upstream_keys_are_not_copied(self):
        fields = {f['source_key']: f for f in self.manifest['fields']}
        address = [fields[f'Address_Line_{i}'] for i in range(1, 4)]
        self.assertEqual(len({f['canonical_key'] for f in address}), 3)
        self.assertEqual({f['review_unit'] for f in address}, {'administrative_address'})
        self.assertEqual(fields['Operating_Countries']['canonical_key'], 'operating_countries_text')
        self.assertEqual(fields['Advancing_natual_environment']['canonical_key'],
                         'purposes.advancing_natural_environment')
        self.assertIn('LGBTIQA+', fields)
        self.assertNotIn('Gay_Lesbian_Bisexual', fields)


if __name__ == '__main__':
    unittest.main()
