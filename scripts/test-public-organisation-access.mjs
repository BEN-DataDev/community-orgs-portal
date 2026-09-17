import assert from 'node:assert/strict';
import { createServer } from 'vite';

const server = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
try {
	const { guardRedirect } = await server.ssrLoadModule('/src/lib/server/guard.ts');
	const check = (pathname, state = {}) =>
		guardRedirect({
			pathname,
			search: '',
			hasSession: false,
			isAnonymous: false,
			aal: null,
			...state
		});
	const org = '/organisations/a93d41a5-47de-49fc-9d73-52b0e0d7553b';
	const paths = [
		'/organisations',
		org,
		...['contact', 'legal', 'finance', 'operations', 'relationships', 'history'].map(
			(section) => `${org}/${section}`
		)
	];
	for (const path of paths) {
		for (const method of ['GET', 'HEAD']) {
			assert.equal(check(path, { method }), null);
			assert.equal(check(`${path}/`, { method }), null);
		}
		assert.equal(
			check(path, { hasSession: true }),
			null,
			'signed-in readers must not redirect to themselves'
		);
		for (const method of ['POST', 'PUT', 'PATCH', 'DELETE']) {
			assert.equal(
				check(path, { method, search: '?/save' }),
				`/auth/signin?redirectTo=${encodeURIComponent(path + '?/save')}`
			);
		}
		assert.equal(
			check(path, { hasSession: true, aal: { currentLevel: 'aal1', nextLevel: 'aal2' } }),
			`/auth/mfa?redirectTo=${encodeURIComponent(path)}`
		);
	}
	for (const path of ['/account', '/admin/ingestion', '/organisations-private', `${org}/edit`]) {
		assert.equal(check(path), `/auth/signin?redirectTo=${encodeURIComponent(path)}`);
	}
	assert.equal(check('/auth/signin', { method: 'POST' }), null);
	assert.equal(check('/auth/signin', { hasSession: true }), '/organisations');
	assert.equal(check('/auth/callback', { hasSession: true }), null);
	assert.equal(
		check('/auth/mfa', { hasSession: true, aal: { currentLevel: 'aal1', nextLevel: 'aal2' } }),
		null
	);
	assert.equal(check('/auth/signin', { hasSession: true, isAnonymous: true }), null);
	console.log('Public organisation access guard checks passed.');
} finally {
	await server.close();
}
