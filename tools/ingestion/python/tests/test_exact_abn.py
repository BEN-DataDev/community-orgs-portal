import hashlib
import io
import json
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest.mock import Mock
from urllib.error import HTTPError

from ingestion.adapters.abn import MAX_BYTES, NS, OPERATION, SOAP, normalise_abn, parse_response, request_body
from ingestion.exact_abn import CONTRACT, Transport, acquire, write_bundle

ABN = '34241177887'  # Official edge-case reference; all payloads here are synthetic.
GUID = '11111111-2222-3333-4444-555555555555'


def response(extra='', exception=None):
    entity = (f'<ABN><identifierValue>{ABN}</identifierValue><isCurrentIndicator>Y</isCurrentIndicator></ABN>'
              '<entityStatus><entityStatusCode>Active</entityStatusCode><effectiveFrom>2000-01-01</effectiveFrom></entityStatus>')
    content = f'<businessEntity202001>{entity}{extra}</businessEntity202001>'
    if exception:
        content = f'<exception><exceptionCode>{exception[0]}</exceptionCode><exceptionDescription>{exception[1]}</exceptionDescription></exception>'
    return (f'<s:Envelope xmlns:s="{SOAP}"><s:Body><SearchByABNv202001Response xmlns="{NS}">'
            '<ABRPayloadSearchResults><request><authenticationGUID>' + GUID + '</authenticationGUID></request>'
            '<response><dateRegisterLastUpdated>2026-09-17</dateRegisterLastUpdated>'
            '<dateTimeRetrieved>2026-09-18T00:00:00Z</dateTimeRetrieved>' + content +
            '</response></ABRPayloadSearchResults></SearchByABNv202001Response></s:Body></s:Envelope>').encode()


class Reply(io.BytesIO):
    status = 200


class ParserTests(unittest.TestCase):
    def test_checksum(self):
        self.assertEqual(normalise_abn('34 241 177 887'), ABN)
        for value in ['00000000000', '34241177888', '３４２４１１７７８８７', 34241177887, '34\t241177887']:
            self.assertIsNone(normalise_abn(value))

    def test_suppressed(self):
        result = parse_response(response(), ABN)
        self.assertEqual(result['outcome'], 'success')
        self.assertEqual(result['projection']['names']['mainName'], [])
        self.assertNotIn(GUID, json.dumps(result))
        self.assertEqual(result['response_sha256'], hashlib.sha256(response()).hexdigest())

    def test_lists_mapping_dates_and_nil(self):
        extra = ('<entityType><entityDescription>Other Incorporated Entity</entityDescription></entityType>'
                 '<ACNCRegistration><status>Registered</status><effectiveFrom>2012-12-03</effectiveFrom></ACNCRegistration>'
                 '<mainName><organisationName>Synthetic holder</organisationName></mainName>'
                 '<businessName><organisationName>Old</organisationName><effectiveTo>2001-01-01</effectiveTo></businessName>'
                 '<businessName><organisationName>New</organisationName></businessName>'
                 '<mainTradingName xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:nil="true"/>')
        projection = parse_response(response(extra), ABN)['projection']
        self.assertEqual(projection['entity_type_description'], 'Other Incorporated Entity')
        self.assertEqual(projection['acnc_registration'][0]['status'][0]['#text'], 'Registered')
        self.assertEqual(len(projection['names']['mainName']), 1)
        self.assertEqual(len(projection['names']['businessName']), 2)
        self.assertIn('effectiveTo', projection['names']['businessName'][0])
        self.assertIn('@attributes', projection['names']['mainTradingName'][0])

    def test_failure_outcomes(self):
        for exception, expected in [(('SEARCH', 'No records found'), 'no_match'),
                                    (('WEBSERVICES', 'The GUID entered is not recognised as a Registered Party'), 'invalid_guid'),
                                    (('SEARCH', 'Other error'), 'provider_exception')]:
            self.assertEqual(parse_response(response(exception=exception), ABN)['outcome'], expected)
        for raw in [b'bad', response().replace(b'businessEntity202001', b'businessEntity201408'),
                    response().replace(NS.encode(), b'urn:wrong'),
                    b'<!DOCTYPE x [<!ENTITY x "test">]>' + response()]:
            self.assertEqual(parse_response(raw, ABN)['outcome'], 'malformed_xml')
        self.assertEqual(parse_response(response(), '51824753556')['outcome'], 'identity_mismatch')
        self.assertEqual(parse_response(b'x' * (MAX_BYTES + 1), ABN)['outcome'], 'response_too_large')

    def test_request_contract(self):
        operation = ET.fromstring(request_body(ABN, GUID)).find(f'{{{SOAP}}}Body')[0]
        schema = ET.parse(CONTRACT)
        fields = schema.findall(f'.//{{http://www.w3.org/2001/XMLSchema}}element[@name="{OPERATION}"]/'
                                '{http://www.w3.org/2001/XMLSchema}complexType/'
                                '{http://www.w3.org/2001/XMLSchema}sequence/'
                                '{http://www.w3.org/2001/XMLSchema}element')
        self.assertEqual([e.tag.split('}')[1] for e in operation], [e.get('name') for e in fields])
        self.assertEqual(operation[1].text, 'N')

    def test_multiple_statuses_and_replaced_identifiers_are_not_collapsed(self):
        extra = ('<ABN><identifierValue>51824753556</identifierValue>'
                 '<isCurrentIndicator>N</isCurrentIndicator><replacedFrom>2000-01-01</replacedFrom></ABN>'
                 '<entityStatus><entityStatusCode>Cancelled</entityStatusCode>'
                 '<effectiveFrom>1999-01-01</effectiveFrom><effectiveTo>1999-12-31</effectiveTo></entityStatus>')
        result = parse_response(response(extra), ABN)
        self.assertEqual(result['outcome'], 'success')
        self.assertEqual(len(result['entity']['ABN']), 2)
        self.assertEqual(len(result['projection']['statuses']), 2)
        self.assertNotIn('closed', result['projection'])

    def test_fault_dtd_and_duplicate_entities(self):
        fault = f'<s:Envelope xmlns:s="{SOAP}"><s:Body><s:Fault/></s:Body></s:Envelope>'.encode()
        self.assertEqual(parse_response(fault, ABN)['outcome'], 'provider_exception')
        dtd = '<!DOCTYPE x [<!ENTITY x "test">]>' + response().decode()
        self.assertEqual(parse_response(dtd.encode('utf-16'), ABN)['outcome'], 'malformed_xml')
        duplicate = response().replace(b'</response>', b'<businessEntity202001/></response>')
        self.assertEqual(parse_response(duplicate, ABN)['outcome'], 'malformed_xml')


class TransportTests(unittest.TestCase):
    def test_private_response_and_deduplication(self):
        opener = Mock()
        opener.open.return_value = Reply(response())
        transport = Transport(GUID, opener=opener)
        result = acquire([ABN, '34 241 177 887', 'invalid'], GUID, transport)
        self.assertEqual([r['outcome'] for r in result['records']], ['success', 'invalid_abn'])
        self.assertEqual(transport.requests, 1)
        self.assertNotIn(GUID, json.dumps(result))
        request = opener.open.call_args.args[0]
        self.assertNotIn(GUID, request.full_url)
        self.assertIn(GUID.encode(), request.data)
        self.assertFalse(result['publication_eligible'])

    def test_pending_and_caps(self):
        self.assertEqual(acquire([ABN])['records'][0]['outcome'], 'pending_credentials')
        self.assertEqual(acquire([ABN], 'invalid')['records'][0]['outcome'], 'invalid_guid')
        for values in [[], [ABN] * 11, [123]]:
            with self.assertRaises(ValueError):
                acquire(values)

    def test_retries_timeout_and_budget(self):
        opener, pauses = Mock(), []
        opener.open.side_effect = TimeoutError('secret diagnostics')
        transport = Transport(GUID, opener=opener, sleep=pauses.append)
        self.assertEqual(transport.lookup(ABN), {'outcome': 'timeout'})
        self.assertEqual(transport.requests, 3)
        self.assertEqual(pauses, [1, 2])
        transport.end = 0
        self.assertEqual(transport.lookup(ABN)['outcome'], 'budget_exhausted')
        transport.end = float('inf')
        transport.requests = 30
        self.assertEqual(transport.lookup(ABN)['outcome'], 'budget_exhausted')

    def test_size_echo_http_and_fault(self):
        for raw, status, expected in [(b'x' * (MAX_BYTES + 1), 200, 'response_too_large'),
                                      (response(f'<mainName><organisationName>{GUID}</organisationName></mainName>'), 200, 'credential_echo'),
                                      (b'forbidden', 403, 'http_error'),
                                      (response(exception=('WEBSERVICES', 'Provider error')), 500, 'provider_exception')]:
            opener = Mock()
            reply = Reply(raw)
            reply.status = status
            opener.open.return_value = reply
            self.assertEqual(Transport(GUID, opener=opener).lookup(ABN)['outcome'], expected)
        opener = Mock()
        opener.open.side_effect = HTTPError('https://example.test', 500, 'error', {}, Reply(response(exception=('SEARCH', 'No records found'))))
        self.assertEqual(Transport(GUID, opener=opener).lookup(ABN)['outcome'], 'no_match')

    def test_private_bundle(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'bundle'
            write_bundle(path, acquire([ABN]))
            self.assertEqual(path.stat().st_mode & 0o777, 0o700)
            data = path / 'evidence.json'
            self.assertEqual(data.stat().st_mode & 0o777, 0o600)
            manifest = json.loads((path / 'manifest.json').read_text())
            self.assertEqual(manifest['files']['evidence.json'], hashlib.sha256(data.read_bytes()).hexdigest())
            with self.assertRaises(FileExistsError):
                write_bundle(path, {})

    def test_slow_response_and_redirect_are_bounded(self):
        ticks = [0]
        class Slow(Reply):
            def read1(self, size):
                ticks[0] += 11
                return super().read1(size)
        opener = Mock()
        opener.open.side_effect = lambda *args, **kwargs: Slow(response())
        transport = Transport(GUID, opener=opener, clock=lambda: ticks[0], sleep=lambda n: None)
        self.assertEqual(transport.lookup(ABN)['outcome'], 'timeout')
        self.assertEqual(transport.requests, 3)
        from ingestion.live_acnc import NoRedirect
        with self.assertRaises(ValueError):
            NoRedirect().redirect_request(None, None, 302, '', {}, 'https://example.test')


if __name__ == '__main__':
    unittest.main()
