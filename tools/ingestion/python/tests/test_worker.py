import copy
import unittest
from unittest.mock import patch

from ingestion.worker import Database, run_one, run_validation_one
from ingestion.live_acnc import acquire
from test_live_acnc import CONFIG, Reader

JOB = {'id': '00000000-0000-4000-8000-000000000001',
       'lease_token': '00000000-0000-4000-8000-000000000002',
       'config': {**CONFIG, 'enabled': True}, 'checkpoint': None}


class DB:
    def __init__(self, job=JOB, fail=None):
        self.job, self.fail = copy.deepcopy(job), fail
        self.calls = []

    def call(self, function, *args):
        self.calls.append((function, args))
        if function == self.fail:
            raise RuntimeError('secret database diagnostics')
        if function == 'claim_acquisition':
            return self.job
        if function == 'checkpoint_acquisition':
            self.job['checkpoint'] = args[2]
        if function == 'finish_acquisition':
            return 99


class WorkerTests(unittest.TestCase):
    def test_complete_private_staging(self):
        db = DB()
        result = run_one(db, lambda _: Reader())
        self.assertEqual(result['status'], 'complete')
        self.assertEqual(result['run_id'], 99)
        self.assertIn('heartbeat_acquisition', [x[0] for x in db.calls])
        self.assertFalse(db.job['checkpoint']['publication_eligible'])
        self.assertEqual(db.job['checkpoint']['run_id'], 'acnc-job-' + JOB['id'])

    def test_resume_checkpoint_without_fetch(self):
        db = DB()
        run_one(db, lambda _: Reader())
        saved = copy.deepcopy(db.job['checkpoint'])
        def forbidden(_):
            self.fail('must not fetch again')
        self.assertEqual(run_one(db, forbidden)['status'], 'complete')
        self.assertEqual(db.job['checkpoint'], saved)

    def test_lease_loss_stops_source_requests(self):
        reader = Reader()
        db = DB(fail='heartbeat_acquisition')
        result = run_one(db, lambda _: reader)
        self.assertEqual(result['status'], 'worker_error')
        self.assertEqual(reader.requests, 0)
        self.assertNotIn('checkpoint_acquisition', [x[0] for x in db.calls])
        self.assertNotIn('secret', str(result))

    def test_staging_failure_keeps_checkpoint(self):
        db = DB(fail='finish_acquisition')
        self.assertEqual(run_one(db, lambda _: Reader())['status'], 'worker_error')
        self.assertIsNotNone(db.job['checkpoint'])
        self.assertEqual(db.calls[-1][0], 'fail_acquisition')

    def test_partial_evidence_is_retained(self):
        db = DB()
        result = run_one(db, lambda _: Reader(changed=True))
        self.assertEqual(result['status'], 'partial')
        self.assertFalse(db.job['checkpoint']['publication_eligible'])

    def test_idle(self):
        self.assertEqual(run_one(DB(None)), {'status': 'idle'})

    def test_validation_replay_is_staged_separately(self):
        class ReplayDB:
            def __init__(self):
                self.calls = []
            def call(self, function, *args):
                self.calls.append((function, args))
                if function == 'claim_validation_replay':
                    return {'id': JOB['id'], 'lease_token': JOB['lease_token']}
                if function == 'finish_validation_replay':
                    return 101
        envelope = {'completion': 'complete', 'quarantine': [], 'errors': []}
        db = ReplayDB()
        with patch('ingestion.worker.validate'):
            result = run_validation_one(db, lambda _: envelope)
        self.assertEqual(result, {'replay': JOB['id'], 'status': 'complete', 'run_id': 101})
        self.assertEqual(db.calls[-1][0], 'finish_validation_replay')

    def test_failed_validation_replay_is_fenced(self):
        class ReplayDB:
            def __init__(self):
                self.calls = []
            def call(self, function, *args):
                self.calls.append((function, args))
                if function == 'claim_validation_replay':
                    return {'id': JOB['id'], 'lease_token': JOB['lease_token']}
        db = ReplayDB()
        result = run_validation_one(db, lambda _: (_ for _ in ()).throw(ValueError('private evidence')))
        self.assertEqual(result['status'], 'worker_error')
        self.assertNotIn('private evidence', str(result))
        self.assertEqual(db.calls[-1][0], 'fail_validation_replay')

    @patch('ingestion.worker.subprocess.run')
    def test_database_uses_stdin_and_no_credentials_in_arguments(self, run):
        run.return_value.returncode = 0
        run.return_value.stdout = 'null\n'
        self.assertIsNone(Database().call('claim_acquisition'))
        self.assertEqual(run.call_args.args[0], ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1'])
        self.assertIn('SET LOCAL ROLE ingestion_worker', run.call_args.kwargs['input'])
        self.assertEqual(run.call_args.kwargs['timeout'], 45)
