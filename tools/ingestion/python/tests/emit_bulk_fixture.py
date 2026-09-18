"""Synthetic P13 CSV parser output for disposable database staging/replay tests."""
import csv
import io
import json
from pathlib import Path

from ingestion.bulk_acnc import extract
from ingestion.live_acnc import TEXT_FIELDS
from ingestion.staging_sql import expression, validate

root = Path(__file__).resolve().parents[1]
config = json.loads((root / 'config/acnc-pilot.json').read_text())
config.update(resource_id='p13-bulk-fixture', identity_column='ABN', max_bulk_rows=10,
              bulk_url='https://example.org/synthetic.csv')
row = json.loads((root / 'tests/fixtures/acnc-field-coverage.json').read_text())['populated']
row.pop('_id')
row['Postcode'] = config['postcode']
stream = io.StringIO(newline='')
writer = csv.DictWriter(stream, fieldnames=sorted(TEXT_FIELDS))
writer.writeheader()
writer.writerow(row)
stream.seek(0)
envelope = extract(stream, config, 'p13-bulk-fixture', '2026-09-18T00:00:00Z')
envelope['synthetic'] = True
validate(envelope)
assert envelope['completion'] == 'complete'
print("select set_config('test.p13_envelope', (" + expression(envelope) + ")::text, false) is not null;")
