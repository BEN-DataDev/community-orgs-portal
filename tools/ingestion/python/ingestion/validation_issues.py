"""Versioned structured validation issue contract shared by staged adapters."""
import hashlib
import json


NON_OVERRIDABLE = {
    'record_scope', 'source_schema', 'mapping_unknown',
    'acquisition_error', 'licence_or_qualification',
}
RESOLUTIONS = {'correct', 'omit', 'defer', 'reject_record'}


def evidence_hash(value):
    encoded = json.dumps(value, sort_keys=True, ensure_ascii=False,
                         separators=(',', ':')).encode()
    return hashlib.sha256(encoded).hexdigest()


def issue(*, code, category, detail, validator, version, source_value,
          native_id=None, row=None, source_key=None, canonical_key=None,
          allowed=('correct', 'omit', 'defer', 'reject_record'), severity='blocking'):
    allowed = list(allowed)
    if category in NON_OVERRIDABLE:
        allowed = []
    if not code or category not in NON_OVERRIDABLE | {
            'field_format', 'missing_required_field', 'duplicate_identity', 'record_integrity'}:
        raise ValueError('invalid structured issue category')
    if severity not in {'warning', 'blocking'} or not set(allowed) <= RESOLUTIONS:
        raise ValueError('invalid structured issue severity or resolutions')
    return {
        'subject': {'native_id': native_id, 'row': row},
        'field': {'source_key': source_key, 'canonical_key': canonical_key},
        'code': code,
        'category': category,
        'severity': severity,
        'source_value': source_value,
        'raw_evidence_hash': evidence_hash(source_value),
        'validator': {'name': validator, 'version': version},
        'allowed_resolutions': allowed,
        'detail': detail,
    }


def validate_contract(value):
    if not isinstance(value, dict) or not isinstance(value.get('subject'), dict):
        raise ValueError('invalid validation issue')
    if not isinstance(value.get('field'), dict) or not isinstance(value.get('validator'), dict):
        raise ValueError('invalid validation issue')
    if value.get('raw_evidence_hash') != evidence_hash(value.get('source_value')):
        raise ValueError('validation issue evidence hash mismatch')
    if value.get('category') in NON_OVERRIDABLE and value.get('allowed_resolutions') != []:
        raise ValueError('non-overridable issue exposes a resolution')
    if not isinstance(value.get('allowed_resolutions'), list) or not set(value['allowed_resolutions']) <= RESOLUTIONS:
        raise ValueError('invalid allowed resolutions')
    return value
