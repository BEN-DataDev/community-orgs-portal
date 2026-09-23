"""Bounded, offline approved CSV importer. Emits private staging evidence, never publishes."""
import argparse
import csv
import hashlib
import io
import json
import re
from collections import Counter
from datetime import datetime
from pathlib import Path
from urllib.parse import urlsplit

from ingestion.adapters.acnc import digest
from ingestion.validation_issues import issue

COLUMNS = ('source_record_id entity_name entity_kind abn incorporation_jurisdiction '
           'incorporation_number website locality state postcode scope_basis service_area '
           'category description evidence_ref source_modified_at').split()
PARSER = 'approved-csv-v1'
MAX_BYTES = 5 * 1024 * 1024
MAX_ROWS = 10000


def timestamp(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z', value):
        raise ValueError('timestamp must be RFC3339 UTC')
    datetime.fromisoformat(value.replace('Z', '+00:00'))


def required(obj, keys):
    if not isinstance(obj, dict):
        raise ValueError('metadata must be an object')
    for key in keys:
        if not isinstance(obj.get(key), str) or not obj[key].strip():
            raise ValueError(f'missing {key}')


def validate_manifest(m, data, filename):
    required(m, ['source_id', 'resource_id', 'publisher', 'attribution', 'observation_basis',
                 'retention', 'technical_contact', 'observed_at'])
    if m.get('manifest_version') != 'p04-csv-qualification-v1':
        raise ValueError('unsupported manifest version')
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,99}', m['source_id']) or m['source_id'] == 'acnc-register':
        raise ValueError('invalid CSV source_id')
    timestamp(m['observed_at'])
    if type(m.get('synthetic')) is not bool or m.get('publication_eligible') is not False:
        raise ValueError('explicit synthetic flag and publication_eligible=false required')
    status = 'development_fixture_only' if m['synthetic'] else 'approved'
    if m.get('access_status') != status:
        raise ValueError('source access/reuse is not approved')
    required(m.get('licence'), ['basis', 'permitted_use', 'terms_ref'])
    if not m['synthetic']:
        required(m, ['approved_by', 'approved_at', 'access_evidence_ref'])
        timestamp(m['approved_at'])
    if not isinstance(m.get('scope'), dict) or m['scope'].get('complete_snapshot') is not False:
        raise ValueError('CSV v1 requires an explicitly bounded, non-complete snapshot scope')
    required(m['scope'], ['kind', 'intended_pilot'])
    if not isinstance(m.get('files'), dict) or m['files'].get(filename) != hashlib.sha256(data).hexdigest():
        raise ValueError('CSV file hash does not match qualification manifest')
    if type(m.get('row_count')) is not int or not 0 <= m['row_count'] <= MAX_ROWS:
        raise ValueError('invalid row_count')


def row_errors(row):
    errors = []
    for key in ['source_record_id', 'entity_name', 'entity_kind', 'scope_basis', 'evidence_ref']:
        if not row[key]:
            errors.append(f'missing {key}')
    if row['entity_kind'] not in {'legal_entity', 'community_group', 'branch', 'service'}:
        errors.append('invalid entity_kind')
    if row['scope_basis'] not in {'located_in', 'serves_area', 'unknown'}:
        errors.append('invalid scope_basis')
    for key, pattern in [('abn', r'[0-9]{11}'), ('postcode', r'[0-9]{4}')]:
        if row[key] and not re.fullmatch(pattern, row[key]):
            errors.append(f'invalid {key} format')
    if row['state'] and row['state'] not in {'NSW', 'VIC', 'QLD', 'SA', 'WA', 'TAS', 'NT', 'ACT'}:
        errors.append('invalid state')
    if bool(row['incorporation_jurisdiction']) != bool(row['incorporation_number']) or row['incorporation_jurisdiction'] not in {'', 'NSW'}:
        errors.append('incorporation number requires NSW jurisdiction and vice versa')
    if row['source_modified_at']:
        try:
            timestamp(row['source_modified_at'])
        except ValueError:
            errors.append('invalid source_modified_at')
    if row['website']:
        try:
            url = urlsplit(row['website'])
            if (url.scheme not in {'http', 'https'} or not url.hostname or url.username is not None
                    or url.password is not None or any(c.isspace() for c in row['website'])):
                raise ValueError()
            url.port
        except ValueError:
            errors.append('website must be an absolute HTTP(S) URL without credentials')
    return errors


def row_issue(row, index, message):
    key = next((name for name in COLUMNS if name in message), None)
    canonical = key if key in {'entity_name', 'abn', 'website'} else ('csv_' + key if key else None)
    category, code, validator = 'field_format', 'csv.field_invalid', 'approved_csv_field'
    allowed = ('correct', 'omit', 'defer', 'reject_record')
    if message.startswith('missing '):
        category, code, validator = 'missing_required_field', 'csv.required_field_missing', 'required_text'
        allowed = ('correct', 'defer', 'reject_record')
    elif message == 'duplicate source_record_id in file':
        category, code, validator = 'duplicate_identity', 'csv.duplicate_identity', 'source_identity'
        allowed = ('defer', 'reject_record')
    return issue(code=code, category=category, detail=message, validator=validator,
                 version=PARSER, source_value=row.get(key) if key else row,
                 native_id=row.get('source_record_id') or None, row=index,
                 source_key=key, canonical_key=canonical, allowed=allowed)


def extract(data: bytes, manifest: dict, filename='organisations.csv') -> dict:
    if len(data) > MAX_BYTES:
        raise ValueError('CSV exceeds 5 MiB limit')
    validate_manifest(manifest, data, filename)
    try:
        text = data.decode('utf-8-sig')
        if '\x00' in text:
            raise ValueError('NUL bytes are not supported')
        reader = csv.reader(io.StringIO(text, newline=''), strict=True)
        header = next(reader, None)
        if header is None or len(header) != len(COLUMNS) or set(header) != set(COLUMNS):
            raise ValueError('CSV header must contain exactly the v1 columns')
        rows = []
        for values in reader:
            if len(values) != len(header):
                raise ValueError(f'column count mismatch at record {len(rows) + 1}')
            if len(rows) >= MAX_ROWS:
                raise ValueError('CSV exceeds row limit')
            rows.append(dict(zip(header, values)))
    except (UnicodeDecodeError, csv.Error) as exc:
        raise ValueError(f'invalid CSV: {exc}') from exc
    if len(rows) != manifest['row_count']:
        raise ValueError('row count does not match manifest')
    common = {k: manifest[k] for k in ['source_id', 'resource_id', 'observed_at']}
    common.update(parser_version=PARSER, run_id='csv-' + digest({'manifest': manifest, 'parser': PARSER}))
    result = dict(common, contract_version='1.0', publication_eligible=False,
                  synthetic=manifest['synthetic'], qualification=manifest,
                  scope=manifest['scope'], records=[], quarantine=[], errors=[], issues=[], pages=[])
    ids = Counter(row['source_record_id'].strip() for row in rows)
    seen_names = set()
    for index, raw in enumerate(rows, 1):
        row = {key: value.strip() for key, value in raw.items()}
        errors = row_errors(row)
        if ids[row['source_record_id']] > 1:
            errors.append('duplicate source_record_id in file')
        if errors:
            problems = [row_issue(row, index, message) for message in errors]
            result['quarantine'].append({'row': index, 'native_id': row['source_record_id'] or None,
                                         'reason': '; '.join(errors), 'raw': raw,
                                         'raw_sha256': digest(raw), 'issues': problems})
            result['issues'].extend(problems)
            continue
        holds = []
        if row['entity_kind'] in {'branch', 'service'}:
            holds.append('Resolve delivering organisation / branch identity before linking or creating')
        if row['scope_basis'] != 'located_in':
            holds.append('Review geographic eligibility and service evidence')
        name = row['entity_name'].casefold()
        if name in seen_names:
            holds.append('Duplicate name in file; verify distinct identity')
        seen_names.add(name)
        facts = [{'field': key, 'value': row[key], 'source_values': {key: raw[key]}}
                 for key in ['entity_name', 'abn', 'website'] if row[key]]
        # Keep private evidence visible as unmapped assertions in the existing review UI.
        facts += [{'field': 'csv_' + key, 'value': row[key], 'source_values': {key: raw[key]}}
                  for key in COLUMNS if row[key] and key not in {'entity_name', 'abn', 'website', 'source_record_id'}]
        if holds:
            facts.append({'field': 'csv_review_holds', 'value': holds})
        result['records'].append(dict(common, native_id=row['source_record_id'],
            mapping_version='portal-csv-pilot-v1', source_modified_at=row['source_modified_at'] or None,
            source_url=row['evidence_ref'], raw=raw, raw_sha256=digest(raw), assertions=facts,
            disposition='hold' if holds else 'candidate', warnings=holds + ['Identity, scope and fields require review; ABN is unverified']))
    if manifest['synthetic']:
        result['errors'].append({'reason': 'Development fixture only; publication prohibited'})
        result['issues'].append(issue(
            code='qualification.synthetic_fixture', category='licence_or_qualification',
            detail='Development fixture only; publication prohibited',
            validator='csv_qualification', version=PARSER,
            source_value={'synthetic': True}, allowed=()))
    result['completion'] = 'partial' if result['quarantine'] or result['errors'] else 'complete'
    result['counts'] = {'accepted': len(result['records']), 'quarantined': len(result['quarantine']),
                        'source_total': len(rows), 'pages': 0}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--manifest', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--sql-output', type=Path)
    args = parser.parse_args()
    try:
        with args.input.open('rb') as stream:
            data = stream.read(MAX_BYTES + 1)
        if args.manifest.stat().st_size > MAX_BYTES:
            raise ValueError('manifest exceeds size limit')
        result = extract(data, json.loads(args.manifest.read_text(encoding='utf-8')), args.input.name)
        from ingestion.staging_sql import render
        sql = render(result)
    except (ValueError, OSError) as exc:
        parser.exit(2, f'CSV rejected: {exc}\n')
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    if args.sql_output:
        args.sql_output.write_text(sql, encoding='utf-8')
    print(f"{result['completion']}: {result['counts']}")
    return 0 if result['completion'] == 'complete' else 1


if __name__ == '__main__':
    raise SystemExit(main())
