"""Exact ABN SOAP adapter. No startup credentials, discovery, or identity acceptance.

Adapts the assessed ABRClient/format_record approach; see upstream-manifest.json.
All repeated schema fields remain arrays, including singleton responses.
"""
import hashlib
import re
import xml.etree.ElementTree as ET

NS = 'http://abr.business.gov.au/ABRXMLSearch/'
SOAP = 'http://schemas.xmlsoap.org/soap/envelope/'
OPERATION = 'SearchByABNv202001'
VERSION = 'abn-202001-v1'
MAX_BYTES = 2 * 1024 * 1024


def normalise_abn(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9 ]+', value):
        return None
    value = value.replace(' ', '')
    if len(value) != 11 or value == '00000000000':
        return None
    digits = list(map(int, value))
    digits[0] -= 1
    return value if sum(a * b for a, b in zip(digits, [10, 1, 3, 5, 7, 9, 11, 13, 15, 17, 19])) % 89 == 0 else None


def request_body(abn, guid):
    root = ET.Element(f'{{{SOAP}}}Envelope')
    body = ET.SubElement(root, f'{{{SOAP}}}Body')
    operation = ET.SubElement(body, f'{{{NS}}}{OPERATION}')
    for key, value in [('searchString', abn), ('includeHistoricalDetails', 'N'),
                       ('authenticationGuid', guid)]:
        ET.SubElement(operation, f'{{{NS}}}{key}').text = value
    return ET.tostring(root, encoding='utf-8', xml_declaration=True)


def tree(element):
    """Lossless values with stable arrays and explicit XML attributes (including nil)."""
    result = {}
    if element.attrib:
        result['@attributes'] = dict(element.attrib)
    if element.text and element.text.strip():
        result['#text'] = element.text.strip()
    for child in element:
        if not child.tag.startswith('{' + NS + '}'):
            raise ValueError('unexpected namespace')
        result.setdefault(child.tag.split('}', 1)[1], []).append(tree(child))
    return result


def text(element, path):
    return element.findtext('/'.join('{' + NS + '}' + p for p in path.split('/')))


def parse_response(raw, abn):
    """Never return provider text on errors: the response can echo the GUID."""
    result = {'outcome': 'malformed_xml', 'response_sha256': hashlib.sha256(raw).hexdigest()}
    if len(raw) > MAX_BYTES:
        return {**result, 'outcome': 'response_too_large'}
    try:
        # Reject DTD/entity declarations, including UTF-16/32 encodings.
        if b'<!DOCTYPE' in raw.replace(b'\x00', b'').upper() or b'<!ENTITY' in raw.replace(b'\x00', b'').upper():
            return result
        root = ET.fromstring(raw)
        if root.tag != f'{{{SOAP}}}Envelope':
            return result
        body = root.find(f'{{{SOAP}}}Body')
        if body is None or len(body) != 1:
            return result
        if body[0].tag == f'{{{SOAP}}}Fault':
            return {**result, 'outcome': 'provider_exception'}
        if body[0].tag != f'{{{NS}}}{OPERATION}Response':
            return result
        responses = body[0].findall(f'{{{NS}}}ABRPayloadSearchResults/{{{NS}}}response')
        if len(responses) != 1:
            return result
        response = responses[0]
        entities = response.findall(f'{{{NS}}}businessEntity202001')
        exceptions = response.findall(f'{{{NS}}}exception')
        if exceptions:
            if entities or len(exceptions) != 1:
                return result
            code = text(exceptions[0], 'exceptionCode')
            description = (text(exceptions[0], 'exceptionDescription') or '').strip()
            outcome = 'provider_exception'
            if code == 'SEARCH' and description == 'No records found':
                outcome = 'no_match'
            elif code == 'WEBSERVICES' and 'GUID' in description:
                outcome = 'invalid_guid'
            return {**result, 'outcome': outcome}
        if len(entities) != 1:
            return result  # An empty/unrecognised payload is not a no-match result.
        entity = entities[0]
        identifiers = entity.findall(f'{{{NS}}}ABN')
        if not any(text(e, 'identifierValue') == abn for e in identifiers):
            return {**result, 'outcome': 'identity_mismatch'}
        statuses = entity.findall(f'{{{NS}}}entityStatus')
        if not statuses or any(not text(e, 'entityStatusCode') for e in statuses):
            return result
        fields = tree(entity)
        # Canonical mapping consumes actual schema names, avoiding upstream typos.
        projection = {
            'abn': abn,
            'entity_type_description': text(entity, 'entityType/entityDescription'),
            'acnc_registration': fields.get('ACNCRegistration', []),
            'statuses': fields.get('entityStatus', []),
            'names': {key: fields.get(key, []) for key in (
                'legalName', 'mainName', 'businessName', 'mainTradingName', 'otherTradingName')},
        }
        return {**result, 'outcome': 'success', 'entity': fields, 'projection': projection,
                'registry_updated_at': text(response, 'dateRegisterLastUpdated'),
                'registry_retrieved_at': text(response, 'dateTimeRetrieved'),
                'attribution': text(response, 'usageStatement')}
    except (ET.ParseError, ValueError, RecursionError):
        return result
