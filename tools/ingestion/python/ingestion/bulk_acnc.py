"""Explicit, bounded ACNC bulk CSV fallback. Acquisition only; never publishes."""
import argparse
import csv
import hashlib
import io
import json
import re
import tempfile
import uuid
from datetime import datetime, timezone
from http.client import HTTPException
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import Request

from ingestion.acnc_transform import MAPPING_VERSION
from ingestion.acquisition_output import write_outputs
from ingestion.adapters.acnc import digest, normalise
from ingestion.live_acnc import TEXT_FIELDS, Transport, configuration, qualify
from ingestion.staging_sql import validate

PARSER_VERSION = 'acnc-bulk-v1'


def bulk_configuration(raw):
    config = configuration(raw)
    for key, low, high in [('max_bulk_bytes', 1024, 64 * 1024 * 1024),
                           ('max_bulk_rows', 1, 100000)]:
        if type(config.get(key)) is not int or not low <= config[key] <= high:
            raise ValueError(f'{key} must be between {low} and {high}')
    if config.get('identity_column') not in {'_id', 'ABN'}:
        raise ValueError('reviewed identity_column must be _id or ABN')
    url = config.get('bulk_url')
    if not isinstance(url, str) or re.search(r'[\s\\\x00-\x1f\x7f]', url):
        raise ValueError('reviewed bulk_url is required')
    parsed = urlsplit(url)
    # Pin the origin and resource path; never fetch arbitrary metadata URLs.
    if (parsed.scheme != 'https' or parsed.netloc != 'data.gov.au'
            or parsed.query or parsed.fragment
            or not re.fullmatch(r'/data/dataset/[A-Za-z0-9-]+/resource/'
                                + re.escape(config['resource_id'])
                                + r'/download/[A-Za-z0-9_.-]+\.csv', parsed.path)):
        raise ValueError('bulk_url must be a pinned data.gov.au resource CSV download')
    return config


class BulkTransport(Transport):
    def download(self, url, output, max_bytes):
        remaining = self.end - self.clock()
        if remaining <= 0 or self.requests >= self.max_requests:
            raise ValueError('HTTP time/request budget exhausted')
        self.requests += 1
        request = Request(url, headers={'Accept': 'text/csv', 'Accept-Encoding': 'identity',
                                       'User-Agent': 'CommunityOrgsPilot/0.1'})
        # No retry of a partially downloaded file. The operator starts a fresh run.
        try:
            response = self.opener.open(request, timeout=min(remaining, self.config['timeout_seconds']))
        except HTTPError as exc:
            code = exc.code
            exc.close()
            raise ValueError(f'Bulk HTTP {code}; download not retried') from exc
        with response:
            headers = getattr(response, 'headers', {})
            if headers.get('Content-Encoding', 'identity').lower() != 'identity':
                raise ValueError('compressed bulk response requires separate qualification')
            length = headers.get('Content-Length')
            if length is not None and (not length.isdigit() or int(length) > max_bytes):
                raise ValueError('invalid or oversized bulk Content-Length')
            size = 0
            while True:
                if self.clock() >= self.end:
                    raise ValueError('HTTP deadline exhausted')
                chunk = response.read1(min(65536, max_bytes + 1 - size))
                if not chunk:
                    break
                size += len(chunk)
                if size > max_bytes:
                    raise ValueError('bulk response exceeds byte limit')
                output.write(chunk)
            if length is not None and size != int(length):
                raise ValueError('incomplete bulk response: Content-Length mismatch')


def bulk_qualification(payload, config):
    metadata = qualify(payload, config, require_datastore=False)
    if (metadata['resource_url'] != config['bulk_url']
            or str(metadata['resource_format']).upper() != 'CSV'):
        raise ValueError('bulk resource URL/format changed; review required')
    return metadata


def extract(stream, config, run_id, observed_at, *, clock_check=lambda: None):
    """Scan the whole qualified file, retaining only the bounded postcode cohort.

    No row number or made-up CKAN _id is used as identity. ABN-keyed CSV records
    use a separate native namespace and require reviewed links to existing orgs.
    """
    stamp = datetime.fromisoformat(observed_at.replace('Z', '+00:00'))
    if stamp.tzinfo is None or not run_id:
        raise ValueError('run_id and timezone-aware observation are required')
    common = dict(source_id='acnc-register', resource_id=config['resource_id'],
                  run_id=run_id, observed_at=observed_at, parser_version=PARSER_VERSION)
    result = dict(common, contract_version='1.0', publication_eligible=False,
                  synthetic=False, scope={'kind': 'filtered-resource',
                  'portal_scope_revision_id': config['portal_scope_revision_id'],
                  'alignment': config['scope_alignment'],
                  'filters': {'Postcode': config['postcodes']}, 'complete_snapshot': False}, completion='failed',
                  records=[], quarantine=[], errors=[], pages=[])
    rows = selected = 0
    headers = None
    eof = False
    seen = {}
    outside_identity_issues = 0
    try:
        reader = csv.reader(stream, strict=True)
        headers = next(reader, None)
        expected = TEXT_FIELDS | ({'_id'} if config['identity_column'] == '_id' else set())
        if headers is None or len(headers) != len(expected) or set(headers) != expected:
            raise ValueError('bulk CSV header differs from reviewed mapping/identity contract')
        for values in reader:
            clock_check()
            if rows >= config['max_bulk_rows']:
                raise ValueError('bulk row budget exhausted')
            rows += 1
            if len(values) != len(headers) or any('\x00' in v for v in values):
                raise ValueError(f'invalid CSV column count or NUL at row {rows}')
            row = dict(zip(headers, values))
            in_scope = row['Postcode'].strip() in config['postcodes']
            if in_scope:
                selected += 1
                if selected > config['page_size'] * config['max_pages']:
                    raise ValueError('selected record budget exhausted')
            identity = row[config['identity_column']].strip()
            pattern = r'[0-9]{11}' if config['identity_column'] == 'ABN' else r'[0-9]+'
            if not re.fullmatch(pattern, identity):
                if in_scope:
                    result['quarantine'].append({'row': rows, 'raw': row,
                                                 'reason': 'missing or invalid bulk identity'})
                else:
                    outside_identity_issues += 1
                continue
            # Check duplicates across the full file, even outside the selected scope.
            native_id = 'abn:' + identity if config['identity_column'] == 'ABN' else str(int(identity))
            if native_id in seen:
                if in_scope or seen[native_id]:
                    raise ValueError(f'duplicate bulk identity affecting selected scope at row {rows}')
                outside_identity_issues += 1
            seen[native_id] = in_scope
            if not in_scope:
                continue
            try:
                record = normalise(row, native_id=native_id)
                record.update(common, source_modified_at=None, source_url=config['bulk_url'],
                              raw=row, raw_sha256=digest(row))
                result['records'].append(record)
            except ValueError as exc:
                result['quarantine'].append({'row': rows, 'reason': str(exc), 'raw': row})
        eof = True
        result['completion'] = 'partial' if result['quarantine'] else 'complete'
    except (ValueError, UnicodeError, csv.Error, OSError) as exc:
        result['errors'].append({'reason': str(exc)})
        result['completion'] = 'partial' if rows else 'failed'
    result['counts'] = {'accepted': len(result['records']), 'quarantined': len(result['quarantine']),
                        'pages': 0, 'source_total': selected if eof else None}
    result['bulk_scan'] = {'rows_scanned': rows, 'selected_rows': selected,
                           'reached_eof': eof, 'headers': headers,
                           'outside_scope_identity_issues': outside_identity_issues}
    return result


def acquire_bulk(config, transport, run_id, observed_at):
    metadata = file_hash = file_bytes = None
    envelope = None
    try:
        metadata = bulk_qualification(transport.get('package_show', {'id': 'acnc-register'}), config)
        with tempfile.TemporaryFile(mode='w+b') as file:
            transport.download(config['bulk_url'], file, config['max_bulk_bytes'])
            file_bytes = file.tell()
            if file_bytes > config['max_bulk_bytes']:
                raise ValueError('bulk response exceeds byte limit')
            file.seek(0)
            checksum = hashlib.sha256()
            for block in iter(lambda: file.read(65536), b''):
                checksum.update(block)
            file_hash = checksum.hexdigest()
            file.seek(0)
            def check_deadline():
                if transport.clock() >= transport.end:
                    raise ValueError('bulk scan deadline exhausted')
            with io.TextIOWrapper(file, encoding='utf-8-sig', newline='') as text:
                envelope = extract(text, config, run_id, observed_at, clock_check=check_deadline)
        after = bulk_qualification(transport.get('package_show', {'id': 'acnc-register'}), config)
        if metadata != after:
            raise ValueError('source metadata changed during bulk acquisition')
    except (ValueError, TypeError, KeyError, OSError, HTTPException) as exc:
        if envelope is None:
            envelope = extract(io.StringIO(''), config, run_id, observed_at)
            envelope['errors'] = []
        envelope['completion'] = 'partial' if envelope['bulk_scan']['rows_scanned'] else 'failed'
        envelope['errors'].append({'reason': str(exc)})
    envelope['qualification'] = {
        'mode': 'bulk-csv', 'metadata': metadata, 'limits': config,
        'identity_column': config['identity_column'], 'file_sha256': file_hash,
        'file_bytes': file_bytes, 'http_requests': transport.requests,
        'snapshot_guaranteed': False, 'mapping_version': MAPPING_VERSION,
        'schema_sha256': digest(envelope['bulk_scan']['headers']),
    }
    validate(envelope)
    return envelope


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--enable', action='store_true')
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    try:
        config = bulk_configuration(json.loads(args.config.read_text()))
    except (ValueError, TypeError, KeyError, OSError) as exc:
        parser.error(f'invalid bulk configuration: {exc}')
    if not config['enabled'] and not args.enable:
        parser.error('source disabled; review configuration and pass --enable for this run')
    args.output_dir.mkdir(mode=0o700, parents=True, exist_ok=False)
    envelope = acquire_bulk(config, BulkTransport(config), 'acnc-bulk-' + str(uuid.uuid4()),
                            datetime.now(timezone.utc).isoformat())
    write_outputs(args.output_dir, envelope)
    print(json.dumps({'completion': envelope['completion'], 'counts': envelope['counts'],
                      'output': str(args.output_dir)}))
    return 0 if envelope['completion'] == 'complete' else 1


if __name__ == '__main__':
    raise SystemExit(main())
