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
	let operator = false,
		saveError = null,
		calls = [];
	const queue = { runs: [], run: null, total: 0, records: [], detail: null, candidates: [] };
	const locals = {
		supabase: {
			rpc: async (name, args) => {
				calls.push([name, args]);
				return name === 'is_ingestion_operator'
					? { data: operator, error: null }
					: name === 'ingestion_review_queue'
						? { data: queue, error: null }
						: { error: saveError };
			}
		}
	};
	const event = { locals, url: new URL('http://localhost/admin/ingestion'), setHeaders: () => {} };
	await assert.rejects(
		() => load(event),
		(e) => e.status === 403
	);
	operator = true;
	assert.equal((await load(event)).queue.total, 0);
	await assert.rejects(
		() => load({ ...event, url: new URL('http://localhost/admin/ingestion?offset=-1') }),
		(e) => e.status === 400
	);
	const values = {
		run: '1',
		version: '2',
		revision: '0',
		decision: 'link',
		organisation: '',
		note: 'Checked'
	};
	const submit = () =>
		actions.default({
			locals,
			request: new Request('http://localhost/admin/ingestion', {
				method: 'POST',
				body: new URLSearchParams(values)
			})
		});
	assert.equal((await submit()).status, 400);
	assert.equal(
		calls.some(([name]) => name === 'save_ingestion_review'),
		false
	);
	values.decision = 'defer';
	assert.match((await submit()).message, /Review saved/);
	saveError = { code: '40001' };
	assert.equal((await submit()).status, 409);
	operator = false;
	await assert.rejects(submit, (e) => e.status === 403);
	console.log(
		'Review route authorization, input validation, empty queue, save and stale revision checks passed.'
	);
} finally {
	await server.close();
}
