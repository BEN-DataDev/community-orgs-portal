import assert from 'node:assert/strict';
import { createServer } from 'vite';
const server = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
try {
	const { load, actions } = await server.ssrLoadModule('/src/routes/admin/sources/+page.server.ts');
	let admin = false;
	let writes = 0;
	let rpcError = null;
	const locals = {
		user: { id: 'admin' },
		supabase: {
			rpc: async (name) => {
				if (name === 'is_platform_admin') return { data: admin, error: null };
				if (name === 'ingestion_source_approvals') return { data: [], error: null };
				writes++;
				return { error: rpcError };
			}
		}
	};
	const event = {
		locals,
		url: new URL('http://localhost/admin/sources?run=6&version=7'),
		setHeaders: () => {}
	};
	const submit = (extra = {}) =>
		actions.default({
			...event,
			request: new Request(event.url, {
				method: 'POST',
				body: new URLSearchParams({
					source: 'acnc-register',
					resource: 'fixture',
					enabled: 'true',
					token: 'a'.repeat(32),
					reason: 'Reviewed',
					confirm: 'yes',
					...extra
				})
			})
		});
	await assert.rejects(
		() => load(event),
		(e) => e.status === 403
	);
	await assert.rejects(
		() => submit(),
		(e) => e.status === 403
	);
	assert.equal(writes, 0);
	admin = true;
	assert.equal((await load(event)).version, '7');
	assert.equal((await submit({ confirm: '' })).status, 400);
	assert.equal((await submit({ reason: ' ' })).status, 400);
	assert.equal(writes, 0);
	assert.match((await submit()).message, /Source enabled/);
	rpcError = { code: '40001' };
	assert.equal((await submit()).status, 409);
	console.log(
		'Source approval authorization, validation, return context, success and stale update checks passed.'
	);
} finally {
	await server.close();
}
