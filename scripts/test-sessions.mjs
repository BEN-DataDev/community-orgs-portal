import assert from 'node:assert/strict';
import { createServer } from 'vite';
const server = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
try {
	const { actions, load } = await server.ssrLoadModule(
		'/src/routes/account/security/+page.server.ts'
	);
	const { actions: signout } = await server.ssrLoadModule(
		'/src/routes/auth/signout/+page.server.ts'
	);
	const { sessionBrowser, sessionTime } = await server.ssrLoadModule(
		'/src/lib/account-sessions.ts'
	);
	let calls = [],
		rpcResult = { data: true, error: null },
		authResult = { error: null };
	const locals = {
		user: { id: 'owner' },
		session: {},
		isAnonymous: false,
		aal: { currentLevel: 'aal1', nextLevel: 'aal1' },
		supabase: {
			rpc: async (...args) => {
				calls.push(['rpc', ...args]);
				return rpcResult;
			},
			auth: {
				signOut: async (...args) => {
					calls.push(['signOut', ...args]);
					return authResult;
				},
				mfa: { listFactors: async () => ({ error: { message: 'unavailable' } }) }
			}
		}
	};
	const invoke = (values, context = locals) => {
		const fields = new FormData();
		for (const [key, value] of Object.entries(values)) fields.set(key, value);
		return actions.default({
			locals: context,
			request: new Request('https://example.test/account/security', {
				method: 'POST',
				body: fields
			})
		});
	};
	const values = { intent: 'revokeSession', sessionId: 'bfc653e6-fd73-43c3-89e2-d4f9b1d5dc54' };
	for (const override of [
		{ user: null },
		{ session: null },
		{ isAnonymous: true },
		{ aal: null },
		{ aal: { currentLevel: 'aal1', nextLevel: 'aal2' } }
	])
		assert.equal((await invoke(values, { ...locals, ...override })).status, 403);
	assert.equal((await invoke({ ...values, sessionId: 'bad' })).status, 400);
	assert.equal((await invoke({ intent: 'unknown' })).status, 400);
	assert.equal(calls.length, 0);
	assert.equal((await invoke(values)).sessionMessage, 'Session signed out.');
	assert.deepEqual(calls.pop(), [
		'rpc',
		'revoke_account_session',
		{ p_session_id: values.sessionId }
	]);
	rpcResult = { data: false, error: null };
	assert.match((await invoke(values)).sessionMessage, /no longer/);
	rpcResult = { error: { message: 'private database detail' } };
	assert.equal((await invoke(values)).status, 400);
	calls = [];
	assert.equal((await invoke({ intent: 'signOutAll' })).status, 403);
	assert.equal(calls.length, 1, 'Revoked caller must not reach Auth sign-out');
	rpcResult = { data: [], error: null };
	calls = [];
	assert.match((await invoke({ intent: 'signOutOthers' })).sessionMessage, /remains signed in/);
	assert.deepEqual(calls, [
		['rpc', 'get_account_sessions'],
		['signOut', { scope: 'others' }]
	]);
	await assert.rejects(
		() => invoke({ intent: 'signOutAll' }),
		(e) => e.status === 303 && e.location === '/auth/signin'
	);
	assert.deepEqual(calls.at(-1), ['signOut', { scope: 'global' }]);
	authResult = { error: { message: 'failed' } };
	assert.equal((await invoke({ intent: 'signOutAll' })).status, 400);
	assert.equal((await signout.default({ locals })).status, 400);
	assert.deepEqual(calls.at(-1), ['signOut', { scope: 'local' }]);
	authResult = { error: null };
	await assert.rejects(
		() => signout.default({ locals }),
		(e) => e.status === 303 && e.location === '/'
	);
	rpcResult = { error: { message: 'unavailable' } };
	const page = await load({
		locals,
		setHeaders: (headers) => assert.equal(headers['cache-control'], 'private, no-store')
	});
	assert.equal(page.accountSessions, null);
	assert.equal(page.factorsUnavailable, true);
	assert.equal(sessionBrowser('node'), 'Browser details unavailable');
	assert.equal(sessionBrowser('<script>alert(1)</script>'), 'Browser details unavailable');
	assert.match(
		sessionBrowser('Mozilla/5.0 (Windows NT 10.0) Chrome/130 Safari/537 Edg/130'),
		/Edge.*Windows/
	);
	assert.match(sessionBrowser('Mozilla/5.0 (iPhone) Version/18 Mobile Safari/604'), /Safari.*iOS/);
	assert.equal(sessionTime('invalid'), 'Unavailable');
	assert.match(sessionTime('2026-01-01T00:00:00Z'), /UTC$/);
	console.log(
		'Session checks passed: access/MFA guards, validation, RPC errors, sign-out scopes, redirects, unavailable state, and browser labels.'
	);
} finally {
	await server.close();
}
