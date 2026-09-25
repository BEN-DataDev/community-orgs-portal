import assert from 'node:assert/strict';
import { createServer } from 'vite';

const server = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});

try {
	const { LocalAvatarProvider, LOCAL_PROVIDER } = await server.ssrLoadModule(
		'/src/lib/server/providers/local.ts'
	);
	const { SUPABASE_PROVIDER, SupabaseDomainDatabase, SupabaseIdentityProvider } =
		await server.ssrLoadModule('/src/lib/server/providers/supabase.ts');
	const { loadAccountAvatar, saveAccountAvatar } = await server.ssrLoadModule(
		'/src/lib/server/account-avatar.ts'
	);

	const capabilityNames = [
		'postgresql',
		'verified_identity',
		'private_storage',
		'scheduler',
		'secret_references',
		'backup_restore',
		'migrations'
	];
	for (const descriptor of [SUPABASE_PROVIDER, LOCAL_PROVIDER]) {
		assert.deepEqual(Object.keys(descriptor.capabilities).sort(), capabilityNames.sort());
		for (const support of Object.values(descriptor.capabilities))
			assert.match(support, /^(supported|external|unsupported)$/);
	}
	assert.equal(SUPABASE_PROVIDER.production, true);
	assert.equal(LOCAL_PROVIDER.production, false);
	assert.equal(LOCAL_PROVIDER.capabilities.verified_identity, 'unsupported');

	const local = new LocalAvatarProvider();
	const user = { id: '00000000-0000-4000-8000-000000000001', identities: [] };
	const bytes = new Uint8Array([1, 2, 3]);
	await saveAccountAvatar(local, user.id, 0, 'upload', bytes);
	const avatar = await loadAccountAvatar(local, user);
	assert.equal(avatar.source, 'upload');
	assert.match(avatar.url, /^local-object:/);
	assert.equal(avatar.revision, 1);
	await assert.rejects(() => saveAccountAvatar(local, user.id, 0, 'initials'));
	await saveAccountAvatar(local, user.id, 1, 'initials');
	assert.equal((await loadAccountAvatar(local, user)).url, null);

	let rpcCall;
	const database = new SupabaseDomainDatabase({
		rpc: async (name, args) => {
			rpcCall = { name, args };
			return { data: true, error: null };
		}
	});
	assert.deepEqual(await database.rpc('is_portal_administrator'), { data: true, error: null });
	assert.deepEqual(rpcCall, { name: 'is_portal_administrator', args: undefined });

	const verifiedUser = { id: user.id, is_anonymous: false };
	const identity = new SupabaseIdentityProvider({
		auth: {
			getSession: async () => ({ data: { session: { access_token: 'redacted', user: {} } } }),
			getUser: async () => ({ data: { user: verifiedUser }, error: null }),
			mfa: {
				getAuthenticatorAssuranceLevel: async () => ({
					data: { currentLevel: 'aal2', nextLevel: 'aal2' }
				})
			}
		}
	});
	const verified = await identity.verifyRequest();
	assert.equal(verified.user.id, user.id);
	assert.equal(verified.aal.currentLevel, 'aal2');
	assert.equal(verified.isAnonymous, false);

	console.log(
		'Provider contract checks passed: capabilities, local storage, Supabase RPC and verified identity.'
	);
} finally {
	await server.close();
}
