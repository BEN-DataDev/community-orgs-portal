"""Synthetic old-parser evidence and its actual Python replay for SQL tests."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from test_reprocess_acnc import original, replay
from ingestion.staging_sql import expression
from ingestion.adapters.acnc import digest
for name, data in [('parent', original()), ('replay', replay(original()))]:
    print(f"select set_config('test.f05_{name}', ({expression(data)})::text, false) is not null;")

parent = original()
record = parent['records'][0]
record['raw']['Charity_Website'] = 'example.org'
record['raw_sha256'] = digest(record['raw'])
for a in record['assertions']:
    if a['field'] == 'website':
        a['value'] = 'example.org'
for name, data in [('parent', parent), ('replay', replay(parent))]:
    print(f"select set_config('test.website_{name}', ({expression(data)})::text, false) is not null;")
