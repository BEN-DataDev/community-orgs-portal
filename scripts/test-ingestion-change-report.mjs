import assert from 'node:assert/strict';
import { createServer } from 'vite';
const server = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
try {
	const { GET } = await server.ssrLoadModule('/src/routes/admin/ingestion/report/+server.ts');
	let operator = false,
		rpcError = null,
		calls = [];
	const data = { report_version: 'p15-v1', records: [], counts: {} };
	const locals = {
		supabase: {
			rpc: async (name, args) => {
				calls.push([name, args]);
				return name === 'is_ingestion_operator' ? { data: operator } : { data, error: rpcError };
			}
		}
	};
	const headers = {};
	const event = (query) => ({
		locals,
		url: new URL(`http://localhost/admin/ingestion/report?${query}`),
		setHeaders: (h) => Object.assign(headers, h)
	});
	await assert.rejects(
		() => GET(event('run=1')),
		(e) => e.status === 403
	);
	assert.equal(calls.length, 1);
	operator = true;
	for (const query of ['', 'run=0', 'run=-1', 'run=1&baseline=no', 'run=9223372036854775808']) {
		await assert.rejects(
			() => GET(event(query)),
			(e) => e.status === 400
		);
	}
	const response = await GET(event('run=2&baseline=1'));
	assert.deepEqual(await response.json(), data);
	assert.equal(headers['cache-control'], 'private, no-store');
	assert.equal(
		response.headers.get('content-disposition'),
		'attachment; filename="ingestion-run-2-changes.json"'
	);
	assert.deepEqual(calls.at(-1), ['ingestion_change_report', { p_run: '2', p_baseline: '1' }]);
	for (const [code, status] of [
		['42501', 403],
		['P0002', 404],
		['22023', 400],
		['XX000', 500]
	]) {
		rpcError = { code, message: 'Private database detail' };
		await assert.rejects(
			() => GET(event('run=2')),
			(e) => e.status === status && !JSON.stringify(e).includes('Private database detail')
		);
	}
	console.log(
		'P15 report download: authorization, validation, private headers, baseline and error mapping passed.'
	);
} finally {
	await server.close();
}
