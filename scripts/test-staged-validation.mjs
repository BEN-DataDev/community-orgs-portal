import assert from 'node:assert/strict';
import { createServer } from 'vite';

const server = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
try {
	const { load, actions } = await server.ssrLoadModule(
		'/src/routes/admin/ingestion/+page.server.ts'
	);
	const calls = [];
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
	const review = { runs: [], run: null, total: 0, records: [], detail: null, candidates: [] };
	const locals = {
		supabase: {
			rpc: async (name, args) => {
				calls.push([name, args]);
				if (name === 'is_ingestion_operator') return { data: true, error: null };
				if (name === 'ingestion_review_queue') return { data: review, error: null };
				if (name === 'validation_issue_queue') return { data: validation, error: rpcError };
				if (name === 'validate_issue_value')
					return { data: { valid: true, message: 'Value passed.' }, error: rpcError };
				if (name === 'create_corrected_run')
					return { data: '00000000-0000-4000-8000-000000000341', error: rpcError };
				return { data: null, error: rpcError };
			}
		}
	};
	const event = {
		locals,
		url: new URL('http://localhost/admin/ingestion?issue_run=30&category=field_format'),
		setHeaders: () => {}
	};
	const data = await load(event);
	assert.equal(data.validation.total, 1);
	assert.equal(calls.find(([name]) => name === 'validation_issue_queue')[1].p_run, '30');
	await assert.rejects(
		() => load({ ...event, url: new URL('http://localhost/admin/ingestion?issue_run=x') }),
		(e) => e.status === 400
	);

	const action = (values) =>
		actions.default({
			locals,
			request: new Request(event.url, {
				method: 'POST',
				body: new URLSearchParams(values)
			})
		});
	assert.equal(
		(await action({ intent: 'validate_issue', issue: 'bad', proposed: 'https://example.org' }))
			.status,
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
	rpcError = { code: '40001' };
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
		'P34a route filters, server validation, revision fencing and corrected-run queue actions passed.'
	);
} finally {
	await server.close();
}
