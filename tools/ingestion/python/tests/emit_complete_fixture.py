"""Emit the F02 synthetic envelope for rollback-only database integration tests."""
import json
from pathlib import Path
from ingestion.adapters.acnc import ACNCExtractor

row = json.loads((Path(__file__).parent / 'fixtures/acnc-field-coverage.json').read_text())['populated']
# Explicit false, a long URL and long unsplit names verify lossless publication.
row.update(PBI='N', Adults='N', Charity_Website='https://example.org/' + 'a' * 300,
           Other_Organisation_Names='Unclassified; name, ' * 200)
envelope = ACNCExtractor(lambda _: {'success': True, 'result': {'total': 1, 'records': [row]}},
                         'f03-complete').extract(filters={'State': 'NT'}, run_id='f03-complete',
                                                 observed_at='2026-09-16T00:00:00Z')
assert envelope['completion'] == 'complete'
print("select set_config('test.f03_envelope', convert_from(decode('" +
      json.dumps(envelope).encode().hex() + "','hex'),'UTF8'), false) is not null;")
