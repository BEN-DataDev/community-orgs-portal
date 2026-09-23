"""Replay retained validation evidence into a separate private ingestion run."""
from copy import deepcopy
from datetime import datetime, timezone

from ingestion.acnc_transform import MAPPING_VERSION
from ingestion.adapters.acnc import normalise as normalise_acnc, digest, PARSER_VERSION
from ingestion.approved_csv import COLUMNS, PARSER as CSV_PARSER, row_errors
from ingestion.validation_issues import evidence_hash


def _apply(raw, resolutions, native_id, row, applied):
    rejections = []
    for resolution in resolutions:
        resolution_native_id = resolution.get('native_id')
        if ((resolution_native_id is not None and resolution_native_id != native_id) or
                (resolution_native_id is None and resolution.get('row') != row)):
            continue
        issue_id = str(resolution.get('issue_id'))
        if issue_id in applied:
            raise ValueError('resolution matched more than one retained record')
        key = resolution.get('source_key')
        if not key or evidence_hash(raw.get(key)) != resolution.get('raw_evidence_hash'):
            raise ValueError('resolution raw evidence changed')
        applied.add(issue_id)
        decision = resolution.get('decision')
        if decision == 'correct':
            raw[key] = resolution.get('proposed_value')
        elif decision == 'omit':
            raw[key] = ''
        elif decision == 'reject_record':
            rejections.append({
                'issue_id': issue_id,
                'revision': resolution.get('revision'),
                'native_id': resolution.get('native_id'),
                'row': resolution.get('row'),
            })
        else:
            raise ValueError('unresolved validation decision')
    return rejections


def _csv_record(raw, common):
    row = {key: str(raw.get(key, '')).strip() for key in COLUMNS}
    errors = row_errors(row)
    if errors:
        raise ValueError('; '.join(errors))
    holds = []
    if row['entity_kind'] in {'branch', 'service'}:
        holds.append('Resolve delivering organisation / branch identity before linking or creating')
    if row['scope_basis'] != 'located_in':
        holds.append('Review geographic eligibility and service evidence')
    facts = [{'field': key, 'value': row[key], 'source_values': {key: raw[key]}}
             for key in ['entity_name', 'abn', 'website'] if row[key]]
    facts += [{'field': 'csv_' + key, 'value': row[key], 'source_values': {key: raw[key]}}
              for key in COLUMNS if row[key] and key not in {'entity_name', 'abn', 'website', 'source_record_id'}]
    if holds:
        facts.append({'field': 'csv_review_holds', 'value': holds})
    return dict(common, native_id=row['source_record_id'], mapping_version='portal-csv-pilot-v1',
                source_modified_at=row['source_modified_at'] or None, source_url=row['evidence_ref'],
                raw=raw, raw_sha256=digest(raw), assertions=facts,
                disposition='hold' if holds else 'candidate', warnings=holds)


def replay(request):
    envelope = deepcopy(request['envelope'])
    resolutions = request['resolutions']
    if envelope.get('completion') == 'failed' or envelope.get('errors'):
        raise ValueError('acquisition failures require a new acquisition')
    if not isinstance(resolutions, list) or not resolutions:
        raise ValueError('resolution snapshot required')
    replay_id = request['id']
    run_id = 'validation-replay-' + replay_id
    originals = []
    for position, record in enumerate(envelope.get('records', [])):
        originals.append((record.get('native_id'), record.get('raw'), record.get('row', position), record))
    for position, record in enumerate(envelope.get('quarantine', [])):
        raw = record.get('raw')
        native_id = record.get('native_id')
        if native_id is None and isinstance(raw, dict):
            native_id = raw.get('_id') if envelope['source_id'] == 'acnc-register' else raw.get('source_record_id')
        originals.append((str(native_id) if native_id is not None else None, raw, record.get('row', position), record))
    result = deepcopy(envelope)
    result.update(run_id=run_id, records=[], quarantine=[], errors=[], issues=[], completion='failed',
                  publication_eligible=False, validation_replay={
                      'id': replay_id, 'parent_run_id': request['parent_run_id'],
                      'parent_envelope_sha256': request['parent_envelope_sha256'],
                      'processed_at': datetime.now(timezone.utc).isoformat(),
                      'resolutions': [{'issue_id': x['issue_id'], 'revision': x['revision']}
                                      for x in resolutions],
                      'rejections': [],
                  })
    seen = set()
    applied = set()
    rejected_records = 0
    for native_id, original_raw, row, old in originals:
        if not isinstance(original_raw, dict):
            raise ValueError('retained raw record unavailable')
        raw = deepcopy(original_raw)
        rejections = _apply(raw, resolutions, native_id, row, applied)
        if rejections:
            result['validation_replay']['rejections'].extend(rejections)
            rejected_records += 1
            continue
        if not native_id or native_id in seen:
            raise ValueError('duplicate or missing identity during full replay')
        seen.add(native_id)
        if envelope['source_id'] == 'acnc-register':
            record = normalise_acnc(raw, native_id=native_id)
            record.update(source_id=envelope['source_id'], resource_id=envelope['resource_id'],
                          run_id=run_id, observed_at=envelope['observed_at'],
                          source_modified_at=old.get('source_modified_at'), parser_version=PARSER_VERSION,
                          source_url=old.get('source_url'), raw_sha256=digest(raw), raw=raw)
        elif envelope.get('parser_version') == CSV_PARSER:
            common = {'source_id': envelope['source_id'], 'resource_id': envelope['resource_id'],
                      'run_id': run_id, 'observed_at': envelope['observed_at'], 'parser_version': CSV_PARSER}
            record = _csv_record(raw, common)
        else:
            raise ValueError('no qualified replay adapter for source')
        result['records'].append(record)
    expected = {str(item.get('issue_id')) for item in resolutions}
    if applied != expected:
        raise ValueError('resolution did not match retained evidence')
    if rejected_records:
        result['validation_replay']['rejections'].sort(key=lambda item: int(item['issue_id']))
        result['scope'] = deepcopy(result['scope'])
        result['scope']['complete_snapshot'] = False
    result['counts'].update(accepted=len(result['records']), quarantined=len(result['quarantine']),
                            rejected=rejected_records)
    result['completion'] = 'complete' if not result['quarantine'] else 'partial'
    result['mapping_version'] = MAPPING_VERSION if envelope['source_id'] == 'acnc-register' else 'portal-csv-pilot-v1'
    return result
