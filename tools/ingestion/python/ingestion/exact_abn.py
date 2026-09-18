"""Bounded exact-ABN acquisition into a private, removable evidence bundle."""
import argparse
import hashlib
import json
import os
import socket
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, build_opener

from ingestion.adapters.abn import MAX_BYTES, NS, OPERATION, VERSION, normalise_abn, parse_response, request_body
from ingestion.live_acnc import NoRedirect

ENDPOINT = 'https://abr.business.gov.au/ABRXMLSearch/AbrXmlSearch.asmx'
CONTRACT = Path(__file__).resolve().parents[1] / 'contracts/abn-202001.wsdl'


class Transport:
    def __init__(self, guid, opener=None, clock=time.monotonic, sleep=time.sleep):
        self.guid, self.clock, self.sleep = guid, clock, sleep
        self.opener = opener or build_opener(NoRedirect())
        self.end = clock() + 90
        self.requests = 0

    def lookup(self, abn):
        for attempt in range(3):
            remaining = self.end - self.clock()
            if remaining <= 0 or self.requests >= 30:
                return {'outcome': 'budget_exhausted'}
            self.requests += 1
            request_end = min(self.end, self.clock() + 10)
            request = Request(ENDPOINT, data=request_body(abn, self.guid), headers={
                'Content-Type': 'text/xml; charset=utf-8', 'SOAPAction': NS + OPERATION})
            outcome = 'transport_error'
            try:
                try:
                    response = self.opener.open(request, timeout=min(10, remaining))
                except HTTPError as exc:
                    # SOAP faults can arrive with HTTP 500; inspect bounded XML first.
                    response = exc
                with response:
                    chunks, size = [], 0
                    while True:
                        remaining_read = request_end - self.clock()
                        if remaining_read <= 0:
                            raise TimeoutError()
                        # HTTPResponse exposes its socket through the buffered reader.
                        # Reset each read to the remaining total request/job budget.
                        fp = getattr(response, 'fp', None)
                        sock = getattr(getattr(fp, 'raw', None), '_sock', None)
                        if sock is not None:
                            sock.settimeout(remaining_read)
                        chunk = response.read1(min(65536, MAX_BYTES + 1 - size))
                        if not chunk:
                            break
                        size += len(chunk)
                        if size > MAX_BYTES:
                            return {'outcome': 'response_too_large'}
                        chunks.append(chunk)
                    raw = b''.join(chunks)
                    parsed = parse_response(raw, abn)
                    # Only response subtree is retained, never echoed request/GUID or raw XML.
                    if self.guid.lower() in json.dumps(parsed).lower():
                        return {'outcome': 'credential_echo'}
                    if response.status == 200 or parsed['outcome'] in {'invalid_guid', 'provider_exception', 'no_match'}:
                        return parsed
                    if response.status not in {429, 500, 502, 503, 504}:
                        return {'outcome': 'http_error'}
                    outcome = 'http_error'
            except (TimeoutError, socket.timeout):
                outcome = 'timeout'
            except URLError as exc:
                outcome = 'timeout' if isinstance(exc.reason, TimeoutError) else 'transport_error'
            except (OSError, ValueError):
                outcome = 'transport_error'
            if attempt == 2:
                return {'outcome': outcome}
            delay = 2 ** attempt
            if self.clock() + delay >= self.end:
                return {'outcome': 'budget_exhausted'}
            self.sleep(delay)
        raise AssertionError('unreachable')


def acquire(abns, guid=None, transport=None):
    if not isinstance(abns, list) or not 1 <= len(abns) <= 10 or any(not isinstance(a, str) for a in abns):
        raise ValueError('supply one to ten ABN strings')
    if guid:
        try:
            guid = str(uuid.UUID(guid))
        except (ValueError, AttributeError):
            return _envelope([{'abn': normalise_abn(a), 'outcome': 'invalid_guid'} for a in abns], 0)
    transport = transport or (Transport(guid) if guid else None)
    records, seen = [], set()
    for value in abns:
        abn = normalise_abn(value)
        if abn and abn in seen:
            continue
        seen.add(abn)
        result = ({'outcome': 'invalid_abn'} if not abn else
                  {'outcome': 'pending_credentials'} if not transport else transport.lookup(abn))
        records.append({'abn': abn, 'observed_at': datetime.now(timezone.utc).isoformat(),
                        'verification': 'pending_review', **result})
    return _envelope(records, transport.requests if transport else 0)


def _envelope(records, requests):
    return {'contract_version': VERSION, 'operation': OPERATION, 'response_version': '202001',
            'wsdl_sha256': hashlib.sha256(CONTRACT.read_bytes()).hexdigest(),
            'source': 'ABN Lookup / Australian Business Register', 'endpoint': ENDPOINT,
            'include_historical_details': 'N', 'publication_eligible': False,
            'automatic_identity_verification': False, 'http_requests': requests,
            'records': records}


def write_bundle(directory, envelope):
    directory.mkdir(mode=0o700, parents=True, exist_ok=False)
    payload = (json.dumps(envelope, indent=2, ensure_ascii=False) + '\n').encode()
    for name, data in [('evidence.json', payload), ('manifest.json', json.dumps({
            'files': {'evidence.json': hashlib.sha256(payload).hexdigest()},
            'abns': [r['abn'] for r in envelope['records']],
            'retention': 'Delete whole bundle on withdrawal; track any reviewed copies separately.',
            'raw_xml_retained': False, 'exports_or_caches_created': False}).encode())]:
        with os.fdopen(os.open(directory / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb') as f:
            f.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--abn', action='append', required=True)
    parser.add_argument('--enable', action='store_true', help='enable a reviewed live set under accepted service terms')
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    try:
        envelope = acquire(args.abn, os.environ.get('ABN_LOOKUP_GUID') if args.enable else None)
        write_bundle(args.output_dir, envelope)
    except (ValueError, OSError):
        parser.exit(1, 'ABN acquisition failed: check inputs and private output directory.\n')
    outcomes = [r['outcome'] for r in envelope['records']]
    print(json.dumps({'outcomes': outcomes, 'http_requests': envelope['http_requests']}))
    return 0 if all(o == 'success' for o in outcomes) else 1


if __name__ == '__main__':
    raise SystemExit(main())
