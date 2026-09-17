import unittest

from ingestion.acnc_transform import transform, MAPPING_VERSION
from ingestion.adapters.acnc import normalise, PARSER_VERSION
from ingestion.field_coverage import load, PACKAGE


class WebsiteNormalisationTests(unittest.TestCase):
    def test_bare_domain_defaults_to_https(self):
        for value in ['example.org', 'www.example.org.au', 'example.org/', 'Example.ORG', 'a-b.example.org']:
            with self.subTest(value=value):
                self.assertEqual(transform(value, 'website_url'), 'https://' + value)
        self.assertEqual(transform('  example.org  ', 'website_url'), 'https://example.org')

    def test_explicit_urls_are_preserved(self):
        for value in ['http://example.org', 'https://example.org/a?q=1#part', 'https://example.org:8443/path']:
            self.assertEqual(transform(value, 'website_url'), value)
        for value in [None, '', '  ']:
            self.assertIsNone(transform(value, 'website_url'))

    def test_ambiguous_and_unsafe_values_are_quarantined(self):
        for value in ['example.org/path', 'example.org?x=1', 'example.org#part',
                      '//example.org', '/example.org', 'example.org:443', 'user@example.org',
                      'https://user:pass@example.org', 'https://example.org:99999',
                      'http://', 'ftp://example.org', 'javascript:alert(1)',
                      'example.org\\evil', 'exa mple.org', 'exa\nmple.org', 'example.org\x00',
                      '127.0.0.1', '[::1]', 'localhost', 'example.local', 'example.invalid',
                      'example.test', 'example.internal', 'example.onion', 'example.org.',
                      '-example.org', 'example-.org', 'example..org', 'example.123',
                      'éxample.org', 'xn--xample-9ua.org', 'a'*64+'.org', ('a'*60+'.')*5+'org']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                transform(value, 'website_url')

    def test_provenance_and_versions_make_the_inference_explicit(self):
        row = load(PACKAGE / 'tests/fixtures/acnc-field-coverage.json')['populated']
        row['Charity_Website'] = 'example.org'
        record = normalise(row)
        website = next(a for a in record['assertions'] if a['field'] == 'website')
        self.assertEqual(PARSER_VERSION, 'acnc-ckan-v3')
        self.assertEqual(MAPPING_VERSION, 'acnc-register-fields-v3')
        self.assertEqual(website['value'], 'https://example.org')
        self.assertEqual(website['source_values'], {'Charity_Website': 'example.org'})
        self.assertEqual(website['normalisation'], {'rule': 'bare-dns-https-v1', 'scheme_inferred': True})
        self.assertTrue(any('scheme defaulted' in w for w in record['warnings']))
        # The legacy rule stays strict for historical v2 evidence.
        with self.assertRaises(ValueError):
            transform('example.org', 'url')
