// Explicitly invoked hosted verification. Secrets stay in a mode-0600 /tmp file.
// prepare creates temporary accounts; test signs in and verifies MFA/report access; cleanup removes them.
import assert from 'node:assert/strict';
import { readFile, writeFile, unlink } from 'node:fs/promises';
import { randomBytes, createHmac } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { createServerClient } from '@supabase/ssr';

const statePath = '/tmp/community-portal-p15-verification.json';
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
		const email = `p15-${role}-${randomBytes(6).toString('hex')}@example.invalid`;
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
	const queue = check(await operator.api.rpc('ingestion_review_queue'), 'operator queue');
	assert.ok(queue.run);
	const run = queue.run;
	const route = `/admin/ingestion/report?run=${run}`;
	assert.equal((await fetch(site + '/organisations')).status, 200);
	const signedOut = await fetch(site + route, { redirect: 'manual' });
	assert.ok([302, 303, 307].includes(signedOut.status));
	assert.equal(
		(await fetch(site + route, { headers: reader.headers(), redirect: 'manual' })).status,
		403
	);
	assert.equal(
		(await reader.api.rpc('ingestion_change_report', { p_run: run })).error?.code,
		'42501'
	);
	const response = await fetch(site + route, { headers: operator.headers() });
	assert.equal(response.status, 200);
	assert.ok(response.headers.get('cache-control').includes('no-store'));
	assert.equal(
		response.headers.get('content-disposition'),
		`attachment; filename="ingestion-run-${run}-changes.json"`
	);
	const report = await response.json();
	assert.equal(report.report_version, 'p15-v1');
	assert.equal(report.run_id, run);
	assert.equal(
		Object.values(report.counts).reduce((a, b) => a + b, 0),
		report.records.length
	);
	assert.equal(report.missing_assessment.assessed, false);
	const direct = check(
		await operator.api.rpc('ingestion_change_report', { p_run: run }),
		'operator report'
	);
	assert.deepEqual(report, direct);
	assert.equal(
		(await fetch(site + route + `&baseline=${run}`, { headers: operator.headers() })).status,
		400
	);
	assert.equal(
		(await fetch(site + '/admin/ingestion/report?run=invalid', { headers: operator.headers() }))
			.status,
		400
	);
	const page = await fetch(site + `/admin/ingestion?run=${run}`, { headers: operator.headers() });
	assert.equal(page.status, 200);
	assert.ok((await page.text()).includes('Download dry-run report'));
	console.log(
		JSON.stringify({
			run,
			counts: report.counts,
			checks:
				'Public route, signed-out redirect, non-operator HTTP/RPC denial, operator report/download headers, matching HTTP/RPC evidence, invalid baseline and queue control passed.'
		})
	);
	const aal1 = (await operator.api.auth.getSession()).data.session.access_token;
	const factor = check(
		await operator.api.auth.mfa.enroll({
			factorType: 'totp',
			friendlyName: 'P15 temporary verification'
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
	const denied = await fetch(url + '/rest/v1/rpc/ingestion_change_report', {
		method: 'POST',
		headers: {
			apikey: anonKey,
			authorization: `Bearer ${aal1}`,
			'content-profile': 'community_orgs',
			'content-type': 'application/json'
		},
		body: JSON.stringify({ p_run: run })
	});
	assert.equal(denied.status, 403);
	check(await operator.api.rpc('ingestion_change_report', { p_run: run }), 'AAL2 report');
	assert.equal((await fetch(site + route, { headers: operator.headers() })).status, 200);
	console.log('Real TOTP verified: retained AAL1 denied; AAL2 RPC and production report passed.');
} else throw new Error('Use prepare, test or cleanup explicitly.');
