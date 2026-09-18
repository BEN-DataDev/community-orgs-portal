// Explicitly invoked hosted verification. Secrets stay in a mode-0600 /tmp file.
// prepare creates two temporary auth accounts; test reads only; cleanup removes them.
import assert from 'node:assert/strict';
import { readFile, writeFile, unlink } from 'node:fs/promises';
import { randomBytes, createHmac } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { createServerClient } from '@supabase/ssr';

const statePath = '/tmp/community-portal-p14-verification.json';
const env = Object.fromEntries(
	(await readFile('.env.production', 'utf8'))
		.split('\n')
		.filter((s) => s && !s.startsWith('#') && s.includes('='))
		.map((s) => {
			const i = s.indexOf('=');
			return [
				s.slice(0, i).trim(),
				s
					.slice(i + 1)
					.trim()
					.replace(/^['"]|['"]$/g, '')
			];
		})
);
const url = env.PUBLIC_SUPABASE_URL;
assert.equal(url, 'https://gqltsfijginclwszrcfj.supabase.co');
const admin = createClient(url, env.PRIVATE_SUPABASE_SERVICE_ROLE_KEY, {
	auth: { persistSession: false, autoRefreshToken: false }
});
const anonKey = env.PUBLIC_SUPABASE_ANON_KEY;
const site = 'https://community-orgs-portal.vercel.app';
function check(result, label) {
	if (result.error) throw new Error(`${label}: ${result.error.message}`);
	return result.data;
}
function client() {
	const jar = new Map();
	const api = createServerClient(url, anonKey, {
		db: { schema: 'community_orgs' },
		auth: { autoRefreshToken: false },
		cookies: {
			getAll: () => [...jar].map(([name, value]) => ({ name, value })),
			setAll: (items) => items.forEach(({ name, value }) => jar.set(name, value))
		}
	});
	return { api, headers: () => ({ cookie: [...jar].map(([k, v]) => `${k}=${v}`).join('; ') }) };
}
function totp(secret) {
	const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
	const bits = [...secret.replace(/=+$/, '').toUpperCase()]
		.map((c) => alphabet.indexOf(c).toString(2).padStart(5, '0'))
		.join('');
	const bytes = Buffer.from((bits.match(/.{8}/g) ?? []).map((b) => parseInt(b, 2)));
	const counter = Buffer.alloc(8);
	counter.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 30000)));
	const hash = createHmac('sha1', bytes).update(counter).digest();
	const offset = hash[19] & 15;
	return ((hash.readUInt32BE(offset) & 0x7fffffff) % 1000000).toString().padStart(6, '0');
}
const mode = process.argv[2];
if (mode === 'prepare') {
	const state = { accounts: [] };
	// O_EXCL prevents overwriting credentials needed to clean up a previous attempt.
	await writeFile(statePath, JSON.stringify(state), { mode: 0o600, flag: 'wx' });
	for (const role of ['operator', 'reader']) {
		const email = `p14-${role}-${randomBytes(6).toString('hex')}@example.invalid`;
		const password = randomBytes(32).toString('base64url');
		const { user } = check(
			await admin.auth.admin.createUser({ email, password, email_confirm: true }),
			'create temporary account'
		);
		state.accounts.push({ id: user.id, email, password, role });
		await writeFile(statePath, JSON.stringify(state), { mode: 0o600 });
	}
	console.log(JSON.stringify(state.accounts.map(({ id, role }) => ({ id, role }))));
} else if (mode === 'cleanup') {
	const state = JSON.parse(await readFile(statePath, 'utf8'));
	for (const account of state.accounts)
		check(await admin.auth.admin.deleteUser(account.id), 'delete temporary account');
	await unlink(statePath);
	console.log('Temporary auth accounts, sessions and factors removed.');
} else if (mode === 'test') {
	const state = JSON.parse(await readFile(statePath, 'utf8'));
	const operator = client(),
		reader = client();
	for (const [role, ctx] of [
		['operator', operator],
		['reader', reader]
	]) {
		const account = state.accounts.find((a) => a.role === role);
		check(
			await ctx.api.auth.signInWithPassword({ email: account.email, password: account.password }),
			`sign in ${role}`
		);
	}
	const route = '/admin/ingestion?run=12&version=18';
	assert.equal((await fetch(site + '/organisations')).status, 200);
	const signedOut = await fetch(site + route, { redirect: 'manual' });
	assert.ok([302, 303, 307].includes(signedOut.status));
	assert.equal(
		(await fetch(site + route, { headers: reader.headers(), redirect: 'manual' })).status,
		403
	);
	assert.equal((await reader.api.rpc('ingestion_identity_inventory')).error?.code, '42501');
	const page = await fetch(site + route, { headers: operator.headers() });
	assert.equal(page.status, 200);
	const html = await page.text();
	assert.ok(html.includes('Identity: match'));
	assert.ok(html.includes('Existing source link'));
	const inventory = check(
		await operator.api.rpc('ingestion_identity_inventory'),
		'operator inventory'
	);
	assert.equal(inventory.classifications.length, 7);
	assert.equal(inventory.claims.length, 7);
	console.log(
		'Production public route, signed-out redirect, reader denial, operator identity queue and private RPC passed.'
	);
	const aal1 = (await operator.api.auth.getSession()).data.session.access_token;
	const factor = check(
		await operator.api.auth.mfa.enroll({
			factorType: 'totp',
			friendlyName: 'P14 temporary verification'
		}),
		'enroll MFA'
	);
	const challenge = check(
		await operator.api.auth.mfa.challenge({ factorId: factor.id }),
		'challenge MFA'
	);
	check(
		await operator.api.auth.mfa.verify({
			factorId: factor.id,
			challengeId: challenge.id,
			code: totp(factor.totp.secret)
		}),
		'verify MFA'
	);
	const denied = await fetch(url + '/rest/v1/rpc/ingestion_identity_inventory', {
		method: 'POST',
		headers: {
			apikey: anonKey,
			authorization: `Bearer ${aal1}`,
			'content-profile': 'community_orgs',
			'content-type': 'application/json'
		},
		body: '{}'
	});
	assert.equal(denied.status, 403);
	check(await operator.api.rpc('ingestion_identity_inventory'), 'AAL2 inventory');
	assert.equal((await fetch(site + route, { headers: operator.headers() })).status, 200);
	console.log('Real TOTP verified: retained AAL1 denied; AAL2 RPC and production queue passed.');
} else throw new Error('Use prepare, test or cleanup explicitly.');
