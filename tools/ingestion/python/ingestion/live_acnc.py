"""Bounded ACNC CKAN acquisition. Writes private evidence, never publishes."""
import argparse
import json
import re
import time
import uuid
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, Request, build_opener

from ingestion.adapters.acnc import ACNCExtractor, digest
from ingestion.acnc_transform import CONTRACT, MAPPING_VERSION
from ingestion.acquisition_output import write_outputs
from ingestion.staging_sql import validate

BASE = 'https://data.gov.au/data/api/3/action/'
TEXT_FIELDS = {f['source_key'] for f in CONTRACT['fields'] if f['source_key'] != '_id'}


def configuration(raw):
    if not isinstance(raw, dict):
        raise ValueError('configuration must be an object')
    if type(raw.get('enabled')) is not bool:
        raise ValueError('enabled must be boolean')
    if not isinstance(raw.get('resource_id'), str):
        raise ValueError('resource_id must be a UUID string')
    uuid.UUID(raw['resource_id'])
    if not isinstance(raw.get('postcode'), str) or not re.fullmatch(r'[0-9]{4}', raw['postcode']):
        raise ValueError('one four-digit postcode is required')
    for key, low, high in [('page_size', 1, 100), ('max_pages', 1, 10),
                           ('timeout_seconds', 1, 20), ('deadline_seconds', 1, 120),
                           ('max_response_bytes', 1024, 4 * 1024 * 1024)]:
        if type(raw.get(key)) is not int or not low <= raw[key] <= high:
            raise ValueError(f'{key} must be between {low} and {high}')
    if raw['page_size'] * raw['max_pages'] > 500:
        raise ValueError('pilot is limited to 500 records')
    if not isinstance(raw.get('expected_licence_title'), str) or not raw['expected_licence_title']:
        raise ValueError('reviewed licence title is required')
    return raw


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('redirect refused; requalify the source endpoint')


class Transport:
    def __init__(self, config, opener=None, clock=time.monotonic, sleep=time.sleep):
        self.config, self.clock, self.sleep = config, clock, sleep
        self.end = clock() + config['deadline_seconds']
        self.opener = opener or build_opener(NoRedirect())
        self.requests = 0
        self.max_requests = (config['max_pages'] + 2) * 3

    def get(self, action, params):
        if action not in {'package_show', 'datastore_search'}:
            raise ValueError('unsupported CKAN action')
        for attempt in range(3):
            remaining = self.end - self.clock()
            if remaining <= 0 or self.requests >= self.max_requests:
                raise ValueError('HTTP time/request budget exhausted')
            self.requests += 1
            retry_after = None
            request = Request(BASE + action + '?' + urlencode(params), headers={
                'Accept': 'application/json', 'User-Agent': 'CommunityOrgsPilot/0.1'})
            try:
                with self.opener.open(request, timeout=min(remaining, self.config['timeout_seconds'])) as response:
                    chunks, size = [], 0
                    while True:
                        if self.clock() >= self.end:
                            raise ValueError('HTTP deadline exhausted')
                        chunk = response.read1(min(65536, self.config['max_response_bytes'] + 1 - size))
                        if not chunk:
                            break
                        size += len(chunk)
                        if size > self.config['max_response_bytes']:
                            raise ValueError('response exceeds byte limit')
                        chunks.append(chunk)
                    result = json.loads(b''.join(chunks))
                if not isinstance(result, dict) or result.get('success') is not True:
                    raise ValueError('CKAN did not report success')
                return result
            except (HTTPError, URLError, TimeoutError, OSError) as exc:
                if isinstance(exc, HTTPError):
                    code = exc.code
                    retry_after = exc.headers.get('Retry-After') if exc.headers else None
                    exc.close()
                    if code not in {429, 500, 502, 503, 504}:
                        raise ValueError(f'HTTP {code}; request not retried') from exc
                if attempt == 2:
                    raise ValueError('HTTP request failed after three attempts') from exc
                pause = 2 ** attempt
                if retry_after:
                    try:
                        requested = float(retry_after) if retry_after.isdigit() else (
                            parsedate_to_datetime(retry_after) - datetime.now(timezone.utc)).total_seconds()
                        pause = max(pause, requested)
                    except (ValueError, TypeError, OverflowError):
                        pass
                if self.clock() + pause >= self.end:
                    raise ValueError('HTTP retry deadline exhausted') from exc
                self.sleep(pause)
        raise AssertionError('unreachable')


def qualify(payload, config, *, require_datastore=True):
    if not isinstance(payload, dict) or payload.get('success') is not True:
        raise ValueError('metadata did not report success')
    data = payload.get('result')
    if not isinstance(data, dict) or data.get('name') != 'acnc-register':
        raise ValueError('unexpected dataset identity')
    if data.get('license_title') != config['expected_licence_title']:
        raise ValueError('source licence changed; review required')
    all_resources = data.get('resources')
    if not isinstance(all_resources, list) or any(not isinstance(r, dict) for r in all_resources):
        raise ValueError('invalid resource metadata')
    resources = [r for r in all_resources if r.get('id') == config['resource_id']]
    if len(resources) != 1 or (require_datastore and resources[0].get('datastore_active') is not True):
        raise ValueError('configured resource is missing or datastore is inactive')
    resource = resources[0]
    return {'dataset_id': data.get('id'), 'metadata_modified': data.get('metadata_modified'),
            'resource_id': resource['id'], 'resource_modified': resource.get('last_modified'),
            'licence_title': data['license_title'], 'licence_url': data.get('license_url'),
            'metadata_sha256': digest(payload), 'resource_name': resource.get('name'),
            'resource_url': resource.get('url'), 'resource_format': resource.get('format')}


def acquire(config, transport, run_id, observed_at):
    metadata = None
    schema = None
    def page(params):
        nonlocal schema
        payload = transport.get('datastore_search', params)
        page_result = payload.get('result')
        if not isinstance(page_result, dict):
            raise ValueError('invalid datastore result')
        rows = page_result.get('records')
        if not isinstance(rows, list):
            raise ValueError('invalid datastore records')
        if any(isinstance(row, dict) and row.get('Postcode') != config['postcode'] for row in rows):
            raise ValueError('response contains a record outside the configured postcode')
        fields = page_result.get('fields', [])
        if not isinstance(fields, list) or any(not isinstance(f, dict) or 'id' not in f or 'type' not in f for f in fields):
            raise ValueError('invalid ACNC field metadata')
        signature = {f['id']: f['type'] for f in fields}
        if len(signature) != len(fields):
            raise ValueError('duplicate schema fields')
        if (set(signature) != TEXT_FIELDS | {'_id'}
                or signature.get('_id') not in {'int', 'int4', 'integer'}
                or any(signature.get(k) != 'text' for k in TEXT_FIELDS)):
            raise ValueError('ACNC field schema changed; review required')
        if schema is not None and signature != schema:
            raise ValueError('schema changed during pagination')
        schema = signature
        return payload
    try:
        metadata = qualify(transport.get('package_show', {'id': 'acnc-register'}), config)
        envelope = ACNCExtractor(page, config['resource_id'], config['page_size'], config['max_pages']).extract(
            filters={'Postcode': config['postcode']}, run_id=run_id, observed_at=observed_at)
        after = qualify(transport.get('package_show', {'id': 'acnc-register'}), config)
        if metadata != after:
            raise ValueError('source metadata changed during acquisition; snapshot is not stable')
    except (ValueError, TypeError, KeyError, OSError) as exc:
        if 'envelope' not in locals():
            def failed_page(_):
                raise ValueError(str(exc))
            envelope = ACNCExtractor(failed_page, config['resource_id'], config['page_size'], 1).extract(
                filters={'Postcode': config['postcode']}, run_id=run_id, observed_at=observed_at)
        else:
            envelope['completion'] = 'partial' if envelope['pages'] else 'failed'
            envelope['errors'].append({'reason': str(exc)})
    envelope['qualification'] = {'metadata': metadata, 'field_types': schema,
                                 'http_requests': transport.requests, 'limits': config,
                                 'mode': 'ckan-pages', 'schema_sha256': digest(schema),
                                 'mapping_version': MAPPING_VERSION,
                                 'snapshot_guaranteed': False}
    envelope['synthetic'] = False
    validate(envelope)
    return envelope


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--enable', action='store_true', help='explicitly enable this acquisition run')
    parser.add_argument('--output-dir', type=Path, required=True, help='new private directory; never overwritten')
    args = parser.parse_args()
    try:
        config = configuration(json.loads(args.config.read_text()))
    except (ValueError, TypeError, KeyError, OSError) as exc:
        parser.error(f'invalid source configuration: {exc}')
    if not config['enabled'] and not args.enable:
        parser.error('source disabled; review configuration and pass --enable for this run')
    args.output_dir.mkdir(mode=0o700, parents=True, exist_ok=False)
    now = datetime.now(timezone.utc).isoformat()
    run_id = 'acnc-' + str(uuid.uuid4())
    envelope = acquire(config, Transport(config), run_id, now)
    write_outputs(args.output_dir, envelope)
    path = args.output_dir / 'envelope.json'
    print(json.dumps({'run_id': run_id, 'completion': envelope['completion'],
                      'counts': envelope['counts'], 'output': str(path), 'errors': envelope['errors']}))
    return 0 if envelope['completion'] == 'complete' else 1


if __name__ == '__main__':
    raise SystemExit(main())
