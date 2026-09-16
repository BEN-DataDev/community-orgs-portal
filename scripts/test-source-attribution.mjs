import assert from 'node:assert/strict';
import { createServer } from 'vite';
const server = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
try {
	const { attributionSchema } = await server.ssrLoadModule('/src/lib/server/source-attribution.ts');
	const source = {
		source_id: 'fixture',
		resource_id: 'fixture',
		title: 'Synthetic test data',
		url: 'javascript:alert(1)',
		licence: 'Fixture',
		licence_url: 'https://user:password@example.org/licence',
		observed_at: '2026-09-16T00:00:00Z',
		published_at: '2026-09-16T01:00:00Z',
		field: 'website',
		unchanged_since_import: false,
		raw: { secret: 'private' }
	};
	const [safe] = attributionSchema.parse([source]);
	assert.equal(safe.url, null);
	assert.equal(safe.licence_url, null);
	assert.equal('raw' in safe, false);
	assert.equal(safe.unchanged_since_import, false);
	const [valid] = attributionSchema.parse([
		{ ...source, url: 'https://example.org/source', licence_url: 'https://example.org/licence' }
	]);
	assert.equal(valid.url, 'https://example.org/source');
	assert.equal(valid.licence_url, 'https://example.org/licence');
	assert.equal(attributionSchema.safeParse([{ ...source, field: null }]).success, false);
	console.log('Attribution URL safety, private-field stripping and response validation passed.');
} finally {
	await server.close();
}
