import assert from 'node:assert/strict';
import { createServer } from 'vite';

// Load the actual SvelteKit endpoint and virtual env modules without binding a port.
const server = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
const originalFetch = globalThis.fetch;
const originalError = console.error;
const originalInfo = console.info;
try {
	const { env } = await server.ssrLoadModule('$env/dynamic/private');
	const { GET } = await server.ssrLoadModule('/src/routes/api/cron/+server.ts');
	const secret = 'cron-regression-test-secret';
	let calls = [];
	let responses = [];
	globalThis.fetch = async (url, options) => {
		calls.push({ url: String(url), headers: new Headers(options.headers) });
		const next = responses.shift();
		assert.ok(next, 'Unexpected database request');
		return new Response(JSON.stringify(next.body), {
			status: next.status ?? 200,
			headers: { 'Content-Type': 'application/json' }
		});
	};
	// Expected failure logs can contain mocked database details; keep test output concise.
	console.error = () => {};
	console.info = () => {};
	const invoke = (authorization) =>
		GET({
			request: new Request('http://localhost/api/cron', {
				headers: authorization ? { Authorization: authorization } : {}
			})
		});
	delete env.CRON_SECRET;
	assert.equal((await invoke(`Bearer ${secret}`)).status, 503);
	env.CRON_SECRET = secret;
	assert.equal((await invoke()).status, 401);
	assert.equal((await invoke('Bearer incorrect')).status, 401);
	assert.equal(calls.length, 0, 'Rejected requests must not reach the database');

	responses = [{ status: 500, body: { message: 'health failed' } }];
	const healthFailure = await invoke(`Bearer ${secret}`);
	assert.equal(healthFailure.status, 500);
	assert.deepEqual(await healthFailure.json(), { success: false, stage: 'health_check' });
	assert.equal(calls.length, 1);

	calls = [];
	responses = [
		{ body: { status: 'healthy' } },
		{ status: 500, body: { message: 'cleanup failed' } }
	];
	const cleanupFailure = await invoke(`Bearer ${secret}`);
	assert.equal(cleanupFailure.status, 500);
	assert.deepEqual(await cleanupFailure.json(), { success: false, stage: 'guest_cleanup' });
	assert.equal(calls.length, 2);

	calls = [];
	responses = [{ body: { status: 'healthy' } }, { body: 0 }];
	const success = await invoke(`Bearer ${secret}`);
	assert.equal(success.status, 200);
	assert.deepEqual(await success.json(), {
		success: true,
		data: { status: 'healthy' },
		purgedAnonymousUsers: 0
	});
	assert.equal(calls.length, 2);
	assert.ok(calls[0].url.endsWith('/rest/v1/rpc/health_check'));
	assert.ok(calls[1].url.endsWith('/rest/v1/rpc/purge_stale_anonymous_users'));
	assert.equal(calls[1].headers.get('content-profile'), 'community_orgs');
	console.log(
		'Cron regression checks passed: authentication, health failure, cleanup failure, and success.'
	);
} finally {
	globalThis.fetch = originalFetch;
	console.error = originalError;
	console.info = originalInfo;
	await server.close();
}
