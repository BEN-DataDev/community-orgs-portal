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
	const portalId = '10000000-0000-4000-8000-000000000001';
	const portalIdentity = {
		portal_id: portalId,
		portal_key: 'test-portal',
		display_name: 'Test Community Portal',
		short_name: 'Test Portal',
		sponsor_name: 'Test Sponsor',
		sponsor_url: null,
		logo_url: null,
		lifecycle_state: 'operational',
		configuration_revision: 7
	};
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

	delete env.PORTAL_ID;
	delete env.PORTAL_KEY;
	responses = [{ body: [portalIdentity] }];
	assert.deepEqual(await (await invoke(`Bearer ${secret}`)).json(), {
		success: false,
		stage: 'portal_identity'
	});
	env.PORTAL_ID = portalId;
	env.PORTAL_KEY = 'test-portal';
	calls = [];
	responses = [{ body: [{ ...portalIdentity, portal_key: 'different-portal' }] }];
	assert.deepEqual(await (await invoke(`Bearer ${secret}`)).json(), {
		success: false,
		stage: 'portal_identity'
	});
	calls = [];

	responses = [{ body: [portalIdentity] }, { status: 500, body: { message: 'health failed' } }];
	const healthFailure = await invoke(`Bearer ${secret}`);
	assert.equal(healthFailure.status, 500);
	assert.deepEqual(await healthFailure.json(), { success: false, stage: 'health_check' });
	assert.equal(calls.length, 2);

	calls = [];
	responses = [
		{ body: [portalIdentity] },
		{ body: { status: 'healthy' } },
		{ status: 500, body: { message: 'cleanup failed' } }
	];
	const cleanupFailure = await invoke(`Bearer ${secret}`);
	assert.equal(cleanupFailure.status, 500);
	assert.deepEqual(await cleanupFailure.json(), { success: false, stage: 'guest_cleanup' });
	assert.equal(calls.length, 3);

	calls = [];
	responses = [
		{ body: [portalIdentity] },
		{ body: { status: 'healthy' } },
		{ body: 0 },
		{ body: [] },
		{ body: 2 }
	];
	const success = await invoke(`Bearer ${secret}`);
	assert.equal(success.status, 200);
	assert.deepEqual(await success.json(), {
		success: true,
		data: { status: 'healthy' },
		portal: {
			portalId,
			portalKey: 'test-portal',
			lifecycleState: 'operational',
			configurationRevision: 7
		},
		purgedAnonymousUsers: 0,
		acquisitions: 2
	});
	assert.equal(calls.length, 5);
	assert.ok(calls[0].url.endsWith('/rest/v1/rpc/get_portal_identity'));
	assert.ok(calls[3].url.endsWith('/rest/v1/rpc/abandoned_account_avatars'));
	assert.ok(calls[1].url.endsWith('/rest/v1/rpc/health_check'));
	assert.ok(calls[2].url.endsWith('/rest/v1/rpc/purge_stale_anonymous_users'));
	assert.equal(calls[2].headers.get('content-profile'), 'community_orgs');
	calls = [];
	responses = [
		{ body: [portalIdentity] },
		{ body: {} },
		{ body: 0 },
		{ status: 500, body: { message: 'avatar lookup failed' } }
	];
	assert.deepEqual(await (await invoke(`Bearer ${secret}`)).json(), {
		success: false,
		stage: 'avatar_cleanup'
	});
	calls = [];
	responses = [
		{ body: [portalIdentity] },
		{ body: {} },
		{ body: 0 },
		{ body: [{ path: 'fixture/avatar-old.webp' }] },
		{ body: [] },
		{ body: 0 }
	];
	assert.equal((await invoke(`Bearer ${secret}`)).status, 200);
	assert.equal(calls.length, 6);
	assert.ok(calls[4].url.endsWith('/storage/v1/object/avatars'));
	calls = [];
	responses = [
		{ body: [portalIdentity] },
		{ body: {} },
		{ body: 0 },
		{ body: [{ path: 'fixture/avatar-old.webp' }] },
		{ status: 403, body: { message: 'delete failed' } }
	];
	assert.deepEqual(await (await invoke(`Bearer ${secret}`)).json(), {
		success: false,
		stage: 'avatar_cleanup'
	});

	responses = [
		{ body: [portalIdentity] },
		{ body: {} },
		{ body: 0 },
		{ body: [] },
		{ status: 500, body: { message: 'queue failed' } }
	];
	assert.deepEqual(await (await invoke(`Bearer ${secret}`)).json(), {
		success: false,
		stage: 'acquisition_queue'
	});

	console.log(
		'Cron regression checks passed: authentication, portal identity, health, cleanup, and success.'
	);
} finally {
	globalThis.fetch = originalFetch;
	console.error = originalError;
	console.info = originalInfo;
	await server.close();
}
