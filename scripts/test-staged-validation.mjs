import assert from 'node:assert/strict';
import { createServer } from 'vite';

const server = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});

try {
	const { load, actions } = await server.ssrLoadModule(
		'/src/routes/admin/ingestion/validation/+page.server.ts'
	);
	const calls = [];
	let operator = true;
	let rpcError = null;
	const validation = {
		total: 1,
		counts: { total: 1, blocking: 1, unresolved: 1, deferred: 0, non_resolvable: 0 },
		issues: [
			{
				id: '41',
				run_id: '30',
				release_id: null,
				subject_native_id: '2242',
				source_row: 14,
				source_key: 'Charity_Website',
				canonical_key: 'website',
				code: 'website.format',
				category: 'field_format',
				severity: 'blocking',
				detail: 'Invalid URL',
				decision: 'unresolved',
				revision: 0
			}
		],
		detail: null
	};
	const readiness = {
		run_id: '30',
		eligible: false,
		raw_evidence_available: true,
		issue_count: 7,
		blocking_count: 7,
		unresolved_blocking_count: 1,
		non_overridable_blocking_count: 0,
		deferred_blocking_count: 0,
		rejected_blocking_count: 0,
		acquisition_failure_count: 0,
		active_replay: null
	};
	const database = {
		rpc: async (name, args) => {
			calls.push([name, args]);
			if (name === 'is_data_steward') return { data: operator, error: null };
			if (name === 'validation_issue_queue') return { data: validation, error: rpcError };
			if (name === 'validation_run_readiness') return { data: readiness, error: rpcError };
			if (name === 'validate_issue_value')
				return { data: { valid: true, message: 'Value passed.' }, error: rpcError };
			if (name === 'create_corrected_run') return { data: '31', error: rpcError };
			return { data: null, error: rpcError };
		}
	};
	const locals = { providers: { database } };
	const event = (path = '/admin/ingestion/validation?issue_run=30&category=field_format') => ({
		locals,
		url: new URL(`http://localhost${path}`),
		setHeaders: () => {}
	});
	const action = (values) =>
		actions.default({
			locals,
			request: new Request('http://localhost/admin/ingestion/validation', {
				method: 'POST',
				body: new URLSearchParams(values)
			})
		});

	const data = await load(event());
	assert.equal(data.queue.total, 1);
	assert.equal(data.readiness, null);
	assert.equal(calls.find(([name]) => name === 'validation_issue_queue')[1].p_run, '30');
	validation.detail = {
		id: '41',
		run_id: '30',
		release_id: null,
		subject_native_id: '2242',
		source_row: 14,
		source_key: 'Charity_Website',
		canonical_key: 'website',
		code: 'website.format',
		category: 'field_format',
		severity: 'blocking',
		source_value: 'example.org',
		raw_evidence_hash: 'a'.repeat(64),
		validator_name: 'http_url',
		validator_version: 'acnc-ckan-v3',
		allowed_resolutions: ['correct', 'omit', 'defer', 'reject_record'],
		detail: 'Invalid URL',
		created_at: '2026-09-23T00:00:00Z',
		resolution: null,
		history: [],
		attempts: []
	};
	const selected = await load(event('/admin/ingestion/validation?issue=41&issue_run=30'));
	assert.equal(selected.readiness.unresolved_blocking_count, 1);
	assert.equal(calls.findLast(([name]) => name === 'validation_run_readiness')[1].p_run, '30');
	await assert.rejects(
		() => load(event('/admin/ingestion/validation?issue_run=x')),
		(error) => error.status === 400
	);
	operator = false;
	await assert.rejects(
		() => load(event()),
		(error) => error.status === 403
	);
	operator = true;

	assert.equal(
		(await action({ intent: 'validate_issue', issue: 'bad', proposed: 'x' })).status,
		400
	);
	assert.equal(
		(await action({ intent: 'validate_issue', issue: '41', proposed: 'https://example.org' }))
			.validationPassed,
		true
	);
	assert.equal(calls.at(-1)[0], 'validate_issue_value');
	assert.match(
		(
			await action({
				intent: 'save_resolution',
				issue: '41',
				revision: '0',
				decision: 'correct',
				proposed: 'https://example.org',
				note: 'Checked'
			})
		).message,
		/Resolution saved/
	);
	assert.equal(calls.at(-1)[1].p_revision, 0);
	assert.match((await action({ intent: 'create_corrected_run', run: '30' })).message, /queued/);
	rpcError = { code: '40001', message: 'stale' };
	assert.equal(
		(
			await action({
				intent: 'save_resolution',
				issue: '41',
				revision: '1',
				decision: 'omit',
				note: 'Stale'
			})
		).status,
		409
	);
	assert.equal((await action({ intent: 'create_corrected_run', run: '30' })).status, 409);
	console.log(
		'Focused validation route filters, authorization, server validation, revision fencing and corrected-run actions passed.'
	);
} finally {
	await server.close();
}
