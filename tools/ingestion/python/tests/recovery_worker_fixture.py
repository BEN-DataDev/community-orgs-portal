"""Fault-injection entry point for scripts/test-acquisition-recovery.py only."""
import json
import os
import sys
import time

from ingestion.worker import Database, run_one
from test_live_acnc import Reader

if os.environ.get('ACQUISITION_DISPOSABLE_TEST') != '1' or os.environ.get('PGHOST') != 'recovery-db':
    raise SystemExit('Disposable recovery harness required')
mode = sys.argv[1]


def interrupt_here(point):
    print(json.dumps({'blocked_at': point}), flush=True)
    while True:
        time.sleep(1)


class FixtureReader(Reader):
    def get(self, action, params):
        if mode == 'resume_checkpoint':
            raise AssertionError('Checkpoint recovery must not contact the source')
        if mode == 'failed':
            raise ValueError('Synthetic source unavailable')
        if action == 'datastore_search' and params['offset'] > 0:
            if mode == 'mid_fetch':
                interrupt_here('after_first_page')
            if mode == 'partial':
                raise ValueError('Synthetic second page failed')
        payload = super().get(action, params)
        if mode in {'changed', 'partial'} and action == 'datastore_search':
            for row in payload['result']['records']:
                row['Charity_Legal_Name'] += ' updated by source'
                if mode == 'partial':
                    row['_id'] = 3  # Fresh, eligible record in an incomplete import.
        return payload


class CheckpointDatabase(Database):
    def call(self, name, *args):
        result = super().call(name, *args)
        if name == 'checkpoint_acquisition' and mode == 'after_checkpoint':
            interrupt_here('checkpoint_committed')
        return result


result = run_one(CheckpointDatabase(), lambda _: FixtureReader())
print(json.dumps(result), flush=True)
raise SystemExit(1 if result['status'] == 'worker_error' else 0)
