"""Execute one bounded acquisition job using a dedicated PostgreSQL worker login.

Connection uses libpq environment/PGSERVICE; credentials never appear in argv.
No publication calls. A supervisor invokes this command periodically.
"""
import json
import subprocess
import sys
import uuid
from datetime import datetime, timezone

from ingestion.live_acnc import Transport, acquire, configuration
from ingestion.staging_sql import expression, validate
from ingestion.validation_replay import replay


class Database:
    def call(self, function, *args):
        if function not in {'claim_acquisition', 'heartbeat_acquisition',
                            'checkpoint_acquisition', 'finish_acquisition', 'fail_acquisition',
                            'claim_validation_replay', 'finish_validation_replay',
                            'fail_validation_replay'}:
            raise ValueError('unsupported worker operation')
        encoded = []
        for value in args:
            encoded.append(expression(value) if isinstance(value, dict) else f"'{uuid.UUID(value)}'::uuid")
        query = ("BEGIN; SET LOCAL ROLE ingestion_worker; SET LOCAL statement_timeout='30s'; "
                 "SET LOCAL lock_timeout='10s'; "
                 f"SELECT to_json(ingestion.{function}({','.join(encoded)})); COMMIT;")
        result = subprocess.run(['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1'],
                                input=query, text=True, capture_output=True, timeout=45)
        if result.returncode:
            # PostgreSQL errors can contain envelope values or connection details.
            raise RuntimeError(f'database operation failed: {function}')
        return json.loads(result.stdout.strip() or 'null')


class LeasedTransport:
    def __init__(self, transport, heartbeat):
        self.transport, self.heartbeat = transport, heartbeat

    @property
    def requests(self):
        return self.transport.requests

    def get(self, action, params):
        self.heartbeat()
        return self.transport.get(action, params)


def run_one(db, transport_factory=Transport, acquire_fn=acquire):
    job = db.call('claim_acquisition')
    if job is None:
        return {'status': 'idle'}
    job_id, token = job['id'], job['lease_token']
    try:
        config = configuration(job['config'])
        envelope = job['checkpoint']
        if envelope is None:
            transport = LeasedTransport(transport_factory(config),
                                       lambda: db.call('heartbeat_acquisition', job_id, token))
            envelope = acquire_fn(config, transport, 'acnc-job-' + job_id,
                                  datetime.now(timezone.utc).isoformat())
            validate(envelope)
            db.call('checkpoint_acquisition', job_id, token, envelope)
        run_id = db.call('finish_acquisition', job_id, token)
        return {'job': job_id, 'status': envelope['completion'], 'run_id': run_id}
    except (ValueError, TypeError, KeyError, OSError, RuntimeError, subprocess.SubprocessError) as exc:
        try:
            db.call('fail_acquisition', job_id, token)
        except (ValueError, OSError, RuntimeError, subprocess.SubprocessError):
            pass  # Expired leases recover on claim; paused jobs are cancelled there.
        # Never print provider payloads, connection strings or credentials.
        return {'job': job_id, 'status': 'worker_error', 'error_type': type(exc).__name__}


def run_validation_one(db, replay_fn=replay):
    job = db.call('claim_validation_replay')
    if job is None:
        return {'status': 'idle'}
    replay_id, token = job['id'], job['lease_token']
    try:
        envelope = replay_fn(job)
        validate(envelope)
        if envelope['completion'] != 'complete' or envelope['quarantine'] or envelope['errors']:
            raise ValueError('corrected run did not pass every validation gate')
        run_id = db.call('finish_validation_replay', replay_id, token, envelope)
        return {'replay': replay_id, 'status': 'complete', 'run_id': run_id}
    except (ValueError, TypeError, KeyError, OSError, RuntimeError, subprocess.SubprocessError) as exc:
        try:
            db.call('fail_validation_replay', replay_id, token)
        except (ValueError, OSError, RuntimeError, subprocess.SubprocessError):
            pass
        return {'replay': replay_id, 'status': 'worker_error', 'error_type': type(exc).__name__}


def main():
    try:
        database = Database()
        result = run_validation_one(database)
        if result['status'] == 'idle':
            result = run_one(database)
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        result = {'status': 'worker_error', 'error_type': type(exc).__name__}
    print(json.dumps(result))
    return 1 if result['status'] in {'worker_error', 'partial', 'failed'} else 0


if __name__ == '__main__':
    sys.exit(main())
