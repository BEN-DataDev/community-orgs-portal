import assert from 'node:assert/strict';
import { createServer } from 'vite';

const server = await createServer({
	optimizeDeps: { noDiscovery: true, include: [] },
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
try {
	const { requireAdminAccess } = await server.ssrLoadModule('/src/lib/server/admin-access.ts');
	const hub = await server.ssrLoadModule('/src/routes/admin/+page.server.ts');
	const review = await server.ssrLoadModule('/src/routes/admin/ingestion/+page.server.ts');
	const jobs = await server.ssrLoadModule('/src/routes/admin/ingestion/jobs/+page.server.ts');
	const sources = await server.ssrLoadModule('/src/routes/admin/sources/+page.server.ts');
	let operator = false;
	let admin = false;
	let capabilityError = null;
	let malformed = false;
	const calls = [];
	const client = {
		rpc: async (name) => {
			calls.push(name);
			if (name === 'is_platform_admin' || name === 'is_ingestion_operator')
				return {
					data: malformed ? 'true' : name === 'is_platform_admin' ? admin : operator,
					error: capabilityError
				};
			if (name === 'ingestion_review_queue')
				return {
					data: { runs: [], run: null, total: 0, records: [], detail: null, candidates: [] }
				};
			if (name === 'acquisition_dashboard') return { data: { sources: [], jobs: [] } };
			if (name === 'ingestion_source_approvals') return { data: [] };
			throw new Error(`Unexpected data or mutation RPC: ${name}`);
		}
	};
	const locals = { user: { id: 'fixture-user' }, isAnonymous: false, supabase: client };
	const headers = {};
	const event = {
		locals,
		url: new URL('http://localhost/admin'),
		setHeaders: (h) => Object.assign(headers, h),
		request: {
			formData: () => {
				throw new Error('Denied request body was read');
			}
		}
	};
	const denied = async (fn) => {
		calls.length = 0;
		await assert.rejects(fn, (e) => e.status === 403);
		assert.ok(calls.every((name) => ['is_platform_admin', 'is_ingestion_operator'].includes(name)));
	};
	const paths = [
		'/admin',
		'/admin/',
		'/admin/ingestion',
		'/admin/ingestion/',
		'/admin/ingestion/jobs',
		'/admin/sources',
		'/admin/ingestion-other',
		'/admin/future-task'
	];
	for (const state of ['no appointment', 'capability RPC failure', 'malformed response']) {
		// Even a truthy payload with an error must not grant authority.
		operator = admin = state !== 'no appointment';
		capabilityError = state === 'capability RPC failure' ? { message: 'unavailable' } : null;
		malformed = state === 'malformed response';
		for (const path of paths) await denied(() => requireAdminAccess(client, locals.user.id, path));
		for (const route of [hub, review, jobs, sources]) {
			await denied(() => route.load(event));
			for (const action of Object.values(route.actions ?? {})) await denied(() => action(event));
		}
	}
	capabilityError = null;
	malformed = false;
	operator = true;
	admin = false;
	for (const path of paths.slice(0, 5)) await requireAdminAccess(client, locals.user.id, path);
	for (const path of paths.slice(5))
		await denied(() => requireAdminAccess(client, locals.user.id, path));
	await hub.load(event);
	assert.equal(headers['cache-control'], 'private, no-store');
	await review.load(event);
	assert.equal((await jobs.load(event)).canConfigure, false);
	await denied(() => jobs.actions.configure(event));
	await denied(() => sources.load(event));
	await denied(() => sources.actions.default(event));

	admin = true;
	for (const path of paths) await requireAdminAccess(client, locals.user.id, path);
	await sources.load(event);
	assert.equal((await jobs.load(event)).canConfigure, true);
	await denied(() => requireAdminAccess(client, undefined, '/admin'));
	await denied(() => hub.load({ ...event, locals: { ...locals, isAnonymous: true } }));
	// Reuse the client/session after revocation: no cached global permission.
	operator = admin = false;
	await denied(() => hub.load(event));
	await denied(() => review.actions.default(event));
	await denied(() => jobs.actions.run(event));
	calls.length = 0;
	await requireAdminAccess(client, undefined, '/organisations');
	assert.equal(calls.length, 0);
	console.log(
		'P07 admin paths, every task loader/action, operator/admin split, RPC failures and revocation passed.'
	);
} finally {
	await server.close();
}
