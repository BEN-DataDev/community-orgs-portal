"""F02 transformations for the declared ACNC register contract.

Errors quarantine the whole record at the extractor boundary. Raw values remain in
its private envelope; assertions never turn invalid or absent values into deletions.
"""
from datetime import date, datetime
import json
from pathlib import Path
import re
from urllib.parse import urlsplit

CONTRACT = json.loads((Path(__file__).parent / 'mappings/acnc-register-v1.json').read_text())
MAPPING_VERSION = CONTRACT['manifest_version']
MONTHS = 'Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec'.split()


def transform(value, rule):
    if value is None:
        return None
    if not isinstance(value, str):
        raise ValueError('expected source string')
    value = value.strip()
    if not value:
        return None
    if rule in {'text', 'other_names', 'countries'}:
        return value
    if rule in {'identifier', 'postcode', 'count'}:
        pattern = {'identifier': r'[0-9]{11}', 'postcode': r'[0-9]{4}', 'count': r'[0-9]+'}[rule]
        if not re.fullmatch(pattern, value):
            raise ValueError(f'invalid {rule}')
        if rule == 'count':
            number = int(value)
            if number > 2147483647:
                raise ValueError('count exceeds database integer range')
            return number
        return value
    if rule == 'flag':
        if value not in {'Y', 'N'}:
            raise ValueError('unqualified flag token; expected Y/N')
        return value == 'Y'
    if rule == 'date':
        if not re.fullmatch(r'[0-9]{2}/[0-9]{2}/[0-9]{4}', value):
            raise ValueError('expected DD/MM/YYYY')
        return datetime.strptime(value, '%d/%m/%Y').date().isoformat()
    if rule == 'calendar':
        if not re.fullmatch(r'[0-9]{2}-[A-Z][a-z]{2}', value) or value[3:] not in MONTHS:
            raise ValueError('expected DD-Mon with English month')
        month, day = MONTHS.index(value[3:]) + 1, int(value[:2])
        date(2000, month, day)  # Leap-day validation, not an asserted reporting year.
        return {'month': month, 'day': day}
    if rule == 'url':
        parsed = urlsplit(value)
        if (parsed.scheme not in {'http', 'https'} or not parsed.hostname
                or parsed.username is not None or parsed.password is not None
                or re.search(r'[\s\\\x00-\x1f\x7f]', value)):
            raise ValueError('expected absolute HTTP(S) URL without credentials')
        _ = parsed.port  # Reject malformed/out-of-range ports.
        return value
    raise ValueError(f'unsupported rule {rule}')


def assertions(row):
    result, address, evidence = [], {}, {}
    known = {f['source_key'] for f in CONTRACT['fields']}
    unknown = sorted(set(row) - known)
    if unknown:
        raise ValueError(f'Unmapped source columns require mapping review: {unknown}')
    for field in CONTRACT['fields']:
        key, canonical = field['source_key'], field['canonical_key']
        if key == '_id':
            continue
        try:
            value = transform(row.get(key), field['transform_rule'])
        except ValueError as exc:
            raise ValueError(f'{key}: {exc}') from exc
        if value is None:
            continue
        if canonical.startswith('administrative_address.'):
            address[canonical.split('.')[1]] = value
            evidence[key] = row[key]
        else:
            result.append({'field': canonical, 'value': value,
                           'source_values': {key: row[key]}, 'mapping_version': MAPPING_VERSION})
    if address:
        result.append({'field': 'administrative_address', 'value': address,
                       'source_values': evidence, 'mapping_version': MAPPING_VERSION})
    return result
