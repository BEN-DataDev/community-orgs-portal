import assert from 'node:assert/strict';
import { createServer } from 'vite';
const server = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
try {
	const { isSiteAdmin, requireOrgEditor } = await server.ssrLoadModule(
		'/src/lib/server/authorization.ts'
	);
	let result = { data: true, error: null };
	const client = { rpc: async () => result };
	assert.equal(await isSiteAdmin(client, 'admin'), true);
	assert.equal(await isSiteAdmin(client, undefined), false);
	result = { data: false, error: null };
	assert.equal(await isSiteAdmin(client, 'org-owner'), false);
	result = { data: true, error: { message: 'unavailable' } };
	assert.equal(await isSiteAdmin(client, 'admin'), false);
	result = { data: 4, error: null };
	assert.equal(await requireOrgEditor(client, 'admin', 'org'), 4);
	result = { data: 0, error: null };
	await assert.rejects(
		() => requireOrgEditor(client, 'other', 'org'),
		(e) => e.status === 403
	);
	console.log('Platform admin navigation, failure denial and organisation editor checks passed.');
} finally {
	await server.close();
}
