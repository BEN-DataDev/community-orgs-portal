"""Replay retained ACNC evidence offline; never fetch, approve or publish facts."""
import argparse
from copy import deepcopy
from datetime import datetime
import json
import os
from pathlib import Path

from ingestion.acnc_transform import CONTRACT, MAPPING_VERSION, transform
from ingestion.adapters.acnc import normalise, digest, PARSER_VERSION
from ingestion.staging_sql import validate, expression


def reprocess(original, *, parent_run_id, run_id, processed_at):
    validate(original)
    if type(parent_run_id) is not int or parent_run_id < 1:
        raise ValueError('positive parent database run ID required')
    if not run_id or run_id == original['run_id']:
        raise ValueError('a new reprocessing run key is required')
    if datetime.fromisoformat(processed_at.replace('Z', '+00:00')).tzinfo is None:
        raise ValueError('processed_at must include timezone')
    if original['completion'] != 'complete':
        raise ValueError('replay requires complete retained acquisition evidence')
    if original['parser_version'] == PARSER_VERSION:
        raise ValueError('replay requires a new parser version')
    result = deepcopy(original)
    result.update(run_id=run_id, parser_version=PARSER_VERSION, records=[], quarantine=[],
                  reprocessing={'parent_run_id': parent_run_id,
                                'parent_run_key': original['run_id'],
                                'parent_parser_version': original['parser_version'],
                                'parent_envelope_sha256': digest(original),
                                'mapping_version': MAPPING_VERSION,
                                'processed_at': processed_at})
    for index, old in enumerate(original['records']):
        # Resource-scoped native identity is authoritative, never ABN/name matching.
        if str(old['raw'].get('_id')) != old['native_id']:
            raise ValueError('retained source identity does not match raw evidence')
        try:
            record = normalise(old['raw'])
        except ValueError as exc:
            result['quarantine'].append({'row': index, 'native_id': old['native_id'],
                                         'raw': deepcopy(old['raw']),
                                         'raw_sha256': old['raw_sha256'], 'reason': str(exc)})
            continue
        record.update({key: deepcopy(old[key]) for key in
                       ('source_id', 'resource_id', 'observed_at', 'source_modified_at',
                        'source_url', 'raw_sha256', 'raw')})
        record.update(run_id=run_id, parser_version=PARSER_VERSION)
        result['records'].append(record)
    result['completion'] = 'partial' if result['quarantine'] else 'complete'
    result['counts'].update(accepted=len(result['records']), quarantined=len(result['quarantine']))
    validate(result)
    return result


def coverage(envelope, workflow=None):
    """Value-free coverage, with independent source and review/publication states.

    workflow is the operator-only ingestion_reprocessing_report RPC result.
    Missing workflow evidence is unknown, never treated as approved/published.
    """
    if workflow is not None and (workflow.get('run_key') != envelope['run_id']
            or any(workflow.get(k) != envelope[k] for k in ('source_id', 'resource_id'))):
        raise ValueError('workflow report belongs to a different run')
    states = {(r['native_id'], f['field']): f for r in (workflow or {}).get('records', [])
              for f in r['fields']}
    fields = {f['source_key']: f for f in CONTRACT['fields'] if f['source_key'] != '_id'}
    records = []
    for record in envelope['records'] + envelope['quarantine']:
        raw = record['raw']
        items = []
        for key in sorted(set(fields) | (set(raw) - {'_id'})):
            f = fields.get(key)
            value = raw.get(key)
            supplied = value is not None and (not isinstance(value, str) or bool(value.strip()))
            status = 'absent'
            if f is None:
                status = 'unmapped'
            elif supplied:
                try:
                    transform(value, f['transform_rule'])
                    status = 'supplied'
                except ValueError:
                    status = 'invalid'
            state = states.get((record['native_id'], f['review_unit'])) if f else None
            items.append({'source_key': key, 'review_unit': f['review_unit'] if f else None,
                          'source_status': status,
                          'review_status': state['status'] if state else None,
                          **{key: state.get(key) if state else None for key in
                             ('approved', 'published', 'previously_published', 'suppressed')}})
        records.append({'native_id': record['native_id'],
                        'quarantined': 'reason' in record, 'fields': items})
    return {'run_key': envelope['run_id'], 'observed_at': envelope['observed_at'],
            'reprocessing': envelope['reprocessing'], 'completion': envelope['completion'],
            'workflow_verified': workflow is not None,
            'source_counts': {s: sum(f['source_status'] == s for r in records for f in r['fields'])
                              for s in ('supplied', 'absent', 'invalid', 'unmapped')},
            'records': records}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True, help='retained acquisition envelope')
    parser.add_argument('--parent-run', type=int, required=True)
    parser.add_argument('--run-key', required=True)
    parser.add_argument('--processed-at', required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    result = reprocess(json.loads(args.input.read_text()), parent_run_id=args.parent_run,
                       run_id=args.run_key, processed_at=args.processed_at)
    args.output_dir.mkdir(mode=0o700, parents=False, exist_ok=False)
    sql = ('BEGIN;\nSET LOCAL ROLE ingestion_worker;\nSELECT ingestion.stage_acnc_reprocessing('
           + str(args.parent_run) + ', ' + expression(result) + ');\nCOMMIT;\n')
    for name, content in [('envelope.json', json.dumps(result, indent=2)),
                          ('coverage.json', json.dumps(coverage(result), indent=2)),
                          ('stage.sql', sql)]:
        with os.fdopen(os.open(args.output_dir / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as out:
            out.write(content)
    print(json.dumps({'completion': result['completion'], 'counts': result['counts']}))


if __name__ == '__main__':
    main()
