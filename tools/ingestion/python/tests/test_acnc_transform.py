import copy
import unittest

from ingestion.acnc_transform import CONTRACT, transform
from ingestion.adapters.acnc import ACNCExtractor, normalise
from ingestion.field_coverage import load, PACKAGE


class TransformTests(unittest.TestCase):
    def setUp(self):
        self.row = load(PACKAGE / 'tests/fixtures/acnc-field-coverage.json')['populated']

    def test_every_public_field_has_typed_assertion_and_original_evidence(self):
        original = copy.deepcopy(self.row)
        facts = {a['field']: a for a in normalise(self.row)['assertions']}
        for f in CONTRACT['fields']:
            if f['source_key'] == '_id':
                continue
            key = f['canonical_key']
            fact = facts[f['review_unit']]
            value = fact['value'][key.split('.')[1]] if key.startswith('administrative_address.') else fact['value']
            self.assertEqual(fact['source_values'][f['source_key']], original[f['source_key']])
            if f['canonical_type'] == 'boolean':
                self.assertIs(value, True)
            self.assertEqual(fact['mapping_version'], CONTRACT['manifest_version'])
        self.assertEqual(self.row, original)
        self.assertEqual(facts['acnc_registered_date']['value'], '1968-05-23')
        self.assertEqual(facts['financial_year_end']['value'], {'month': 6, 'day': 30})
        self.assertEqual(facts['administrative_address']['value']['postcode'], '0800')

    def test_invalid_values_quarantine_with_evidence(self):
        for key, value in [('PBI', 'False'), ('Registration_Date', '31/02/2024'),
                           ('Financial_Year_End', '31-Apr'), ('Postcode', 800),
                           ('Number_of_Responsible_Persons', '-1'),
                           ('Charity_Website', 'https://user:password@example.org'),
                           ('Future_Column', 'requires review')]:
            with self.subTest(key=key):
                row = dict(self.row, **{key: value})
                result = ACNCExtractor(lambda _: {'success': True, 'result': {
                    'total': 1, 'records': [row]}}, 'synthetic').extract(
                    filters={'State': 'NSW'}, run_id='test', observed_at='2026-09-16T00:00:00Z')
                self.assertEqual(result['records'], [])
                self.assertEqual(result['completion'], 'partial')
                self.assertEqual(result['quarantine'][0]['raw'], row)
                self.assertIn(key, result['quarantine'][0]['reason'])

    def test_false_unknown_and_absent_are_distinct(self):
        self.row['PBI'] = 'N'
        self.row['HPC'] = ''
        del self.row['Adults']
        facts = {a['field']: a['value'] for a in normalise(self.row)['assertions']}
        self.assertIs(facts['pbi'], False)
        self.assertNotIn('hpc', facts)
        self.assertNotIn('beneficiaries.adults', facts)
        for value in [None, '', '  ']:
            self.assertIsNone(transform(value, 'flag'))

    def test_declared_formats_and_no_truncation(self):
        self.assertEqual(transform('29/02/2024', 'date'), '2024-02-29')
        self.assertEqual(transform('29-Feb', 'calendar'), {'month': 2, 'day': 29})
        self.assertEqual(transform('0', 'count'), 0)
        self.assertEqual(transform('00000000000', 'identifier'), '00000000000')
        self.assertEqual(transform('A; B, C' * 1000, 'other_names'), 'A; B, C' * 1000)
        self.assertEqual(transform('AUS NZL;unknown', 'countries'), 'AUS NZL;unknown')
        for rule, values in {'flag': ['true', 'false', 'Yes', '0', True],
                             'date': ['2024-02-29', '1/02/2024', '00/00/0000'],
                             'calendar': ['30/06', '30-jun', '00-Jan'],
                             'count': ['+1', '1.5', '2147483648'],
                             'url': ['example.org', 'javascript:alert(1)', 'https://x:99999',
                                     'https://exa mple.org', 'https://x\\evil']}.items():
            for value in values:
                with self.subTest(rule=rule, value=value), self.assertRaises(ValueError):
                    transform(value, rule)
