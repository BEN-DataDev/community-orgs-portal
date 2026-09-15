import assert from 'node:assert/strict';
import sharp from 'sharp';
import { createServer } from 'vite';

const server = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
try {
	const { normaliseAvatar, allowedProviderPhoto, downloadProviderPhoto, providerPhoto } =
		await server.ssrLoadModule('/src/lib/server/avatar-image.ts');
	const { saveAccountAvatar, loadAccountAvatar } = await server.ssrLoadModule(
		'/src/lib/server/account-avatar.ts'
	);
	const { actions } = await server.ssrLoadModule('/src/routes/account/settings/+page.server.ts');
	const image = await sharp({
		create: { width: 1000, height: 800, channels: 3, background: '#336699' }
	})
		.jpeg()
		.withMetadata()
		.toBuffer();
	const encoded = await normaliseAvatar(image, 'image/jpeg');
	const info = await sharp(encoded).metadata();
	assert.equal(info.format, 'webp');
	assert.equal(info.width, 512);
	assert.equal(info.height, 410);
	assert.equal(info.exif, undefined);
	for (const [bytes, type] of [
		[Buffer.from('<svg/>'), 'image/png'],
		[image, 'image/svg+xml'],
		[Buffer.alloc(2097153), 'image/png'],
		[Buffer.alloc(0), 'image/png']
	])
		await assert.rejects(() => normaliseAvatar(bytes, type));
	for (const url of [
		'http://avatars.githubusercontent.com/u/1',
		'https://avatars.githubusercontent.com.evil.example/u/1',
		'https://127.0.0.1/u/1',
		'https://avatars.githubusercontent.com:8443/u/1',
		'https://user:pass@avatars.githubusercontent.com/u/1',
		'https://avatars.githubusercontent.com/../other'
	])
		assert.equal(allowedProviderPhoto(url), null);
	assert.ok(allowedProviderPhoto('https://avatars.githubusercontent.com/u/1?v=4'));
	assert.equal(
		providerPhoto({
			user_metadata: { avatar_url: 'https://avatars.githubusercontent.com/u/1' },
			identities: []
		}),
		null
	);
	const downloaded = await downloadProviderPhoto(
		'https://avatars.githubusercontent.com/u/1',
		async (_, options) => {
			assert.equal(options.redirect, 'error');
			return new Response(image, { headers: { 'content-type': 'image/jpeg' } });
		}
	);
	assert.equal((await sharp(downloaded).metadata()).format, 'webp');
	await assert.rejects(() =>
		downloadProviderPhoto(
			'https://avatars.githubusercontent.com/u/1',
			async () => new Response(Buffer.alloc(2097153), { headers: { 'content-type': 'image/png' } })
		)
	);
	await assert.rejects(() =>
		downloadProviderPhoto(
			'https://avatars.githubusercontent.com/u/1',
			async () => new Response('html', { headers: { 'content-type': 'text/html' } })
		)
	);

	const id = '00000000-0000-4000-8000-000000000001';
	function fixture({
		conflict = false,
		saveError = false,
		uploadError = false,
		deleteError = false
	} = {}) {
		let profile = {
			avatar_path: id + '/avatar-old.webp',
			avatar_source: 'upload',
			avatar_revision: 3,
			avatar_url: null
		};
		const calls = [];

		const selection = {
			single: async () => ({ data: profile }),
			maybeSingle: async () => ({ data: profile })
		};
		const update = (values) => {
			const query = {
				eq: () => query,
				select: () => query,
				maybeSingle: async () => {
					calls.push('save');
					if (saveError) return { error: new Error('network') };
					if (conflict) return { data: null };
					profile = values;
					return { data: { id } };
				}
			};
			return query;
		};
		const client = {
			schema: () => ({ from: () => ({ select: () => ({ eq: () => selection }), update }) }),
			storage: {
				from: () => ({
					upload: async (path, bytes, options) => {
						calls.push('upload');
						assert.ok(path.startsWith(id + '/avatar-'));
						assert.equal(options.upsert, false);
						return { error: uploadError ? new Error('upload') : null };
					},
					remove: async (paths) => {
						calls.push(['remove', ...paths]);
						return { error: deleteError ? new Error('delete') : null };
					},
					createSignedUrl: async () => ({ data: { signedUrl: 'https://example.invalid/signed' } })
				})
			}
		};
		return { client, calls, getProfile: () => profile };
	}
	let f = fixture();
	await saveAccountAvatar(f.client, id, 3, 'upload', encoded);
	assert.equal(f.calls[0], 'upload');
	assert.equal(f.calls[1], 'save');
	assert.equal(f.calls[2][0], 'remove');
	f = fixture({ uploadError: true });
	await assert.rejects(() => saveAccountAvatar(f.client, id, 3, 'upload', encoded));
	assert.deepEqual(f.calls, ['upload']);
	f = fixture({ saveError: true });
	await assert.rejects(() => saveAccountAvatar(f.client, id, 3, 'upload', encoded));
	assert.deepEqual(
		f.calls,
		['upload', 'save'],
		'Ambiguous saves must not delete possibly committed uploads'
	);
	f = fixture({ conflict: true });
	await assert.rejects(() => saveAccountAvatar(f.client, id, 3, 'upload', encoded));
	assert.equal(f.calls[2][0], 'remove');
	assert.notEqual(f.calls[2][1], id + '/avatar-old.webp');
	f = fixture();
	await assert.rejects(() => saveAccountAvatar(f.client, id, 2, 'upload', encoded));
	assert.equal(f.calls.length, 0);
	f = fixture({ deleteError: true });
	assert.equal((await saveAccountAvatar(f.client, id, 3, 'initials')).cleanupPending, true);
	f = fixture();
	const avatar = await loadAccountAvatar(f.client, { id, identities: [] });
	assert.equal(avatar.url, 'https://example.invalid/signed');
	assert.ok(avatar.expiresAt > Date.now());
	await saveAccountAvatar(f.client, id, 3, 'initials');
	assert.equal((await loadAccountAvatar(f.client, { id, identities: [] })).url, null);
	const fields = new FormData();
	fields.set('intent', 'removeAvatar');
	fields.set('avatarRevision', '3');
	const invoke = (locals) =>
		actions.default({
			locals,
			request: new Request('http://localhost/account/settings', { method: 'POST', body: fields })
		});
	assert.equal((await invoke({ user: null })).status, 403);
	assert.equal((await invoke({ user: { id }, isAnonymous: true })).status, 403);
	assert.equal(
		(
			await invoke({
				user: { id },
				isAnonymous: false,
				aal: { currentLevel: 'aal1', nextLevel: 'aal2' }
			})
		).status,
		403
	);
	console.log(
		'Avatar checks passed: decoding, resize/metadata, provider fetch restrictions, failure recovery, concurrent saves, private URLs and action guards.'
	);
} finally {
	await server.close();
}
