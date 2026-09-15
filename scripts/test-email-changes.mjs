import assert from 'node:assert/strict';
import { createServer } from 'vite';
const server = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
try {
	const { actions } = await server.ssrLoadModule('/src/routes/account/settings/+page.server.ts');
	const { GET } = await server.ssrLoadModule('/src/routes/auth/confirm/+server.ts');
	const { load } = await server.ssrLoadModule('/src/routes/auth/email-change/+page.server.ts');
	const { guardRedirect } = await server.ssrLoadModule('/src/lib/server/guard.ts');
	const user = {
		id: 'same-account',
		email: 'current@example.test',
		user_metadata: { avatar_url: 'retained' },
		new_email: ''
	};
	let calls = [];
	let response = { data: { user: { ...user, new_email: 'new@example.test' } }, error: null };
	const locals = {
		user,
		isAnonymous: false,
		aal: { currentLevel: 'aal1', nextLevel: 'aal1' },
		supabase: {
			auth: {
				updateUser: async (...args) => {
					calls.push(['update', ...args]);
					return response;
				},
				resend: async (...args) => {
					calls.push(['resend', ...args]);
					return response;
				}
			}
		}
	};
	const invoke = (values, context = locals) => {
		const fields = new FormData();
		for (const [key, value] of Object.entries(values)) fields.set(key, value);
		const url = new URL('https://portal.example.test/account/settings');
		return actions.default({
			locals: context,
			url,
			request: new Request(url, { method: 'POST', body: fields })
		});
	};
	const values = {
		intent: 'emailChange',
		email: ' New@example.test ',
		emailConfirmation: 'new@example.test'
	};
	assert.equal((await invoke(values, { ...locals, user: null })).status, 403);
	assert.equal((await invoke(values, { ...locals, isAnonymous: true })).status, 403);
	assert.equal(
		(await invoke(values, { ...locals, aal: { currentLevel: 'aal1', nextLevel: 'aal2' } })).status,
		403
	);
	for (const invalid of [
		{ email: 'invalid' },
		{ email: user.email, emailConfirmation: user.email },
		{ emailConfirmation: 'typo@example.test' }
	])
		assert.equal((await invoke({ ...values, ...invalid })).status, 400);
	assert.equal(calls.length, 0);
	const success = await invoke(values);
	assert.ok(success.emailMessage);
	assert.equal(locals.user.email, user.email);
	assert.equal(locals.user.new_email, 'new@example.test');
	assert.equal(locals.user.id, user.id);
	assert.deepEqual(calls[0], [
		'update',
		{ email: 'new@example.test' },
		{ emailRedirectTo: 'https://portal.example.test/auth/email-change' }
	]);
	assert.equal((await invoke(values)).status, 400, 'Pending duplicate should use resend');
	await invoke({ intent: 'emailResend', email: 'attacker@example.test' });
	assert.deepEqual(calls[1], [
		'resend',
		{
			type: 'email_change',
			email: user.email,
			options: { emailRedirectTo: 'https://portal.example.test/auth/email-change' }
		}
	]);
	assert.equal((await invoke({ intent: 'emailResend' }, { ...locals, user })).status, 400);
	response = { error: { status: 429, code: 'over_email_send_rate_limit' } };
	assert.equal((await invoke({ intent: 'emailResend' })).status, 429);
	response = { error: { status: 422, code: 'email_exists', message: 'sensitive backend detail' } };
	assert.ok(!(await invoke({ intent: 'emailResend' })).data.emailError.includes('sensitive'));
	const cookieMap = new Map();
	const cookies = {
		get: (key) => cookieMap.get(key),
		set: (key, value, options) => {
			assert.equal(options.httpOnly, true);
			cookieMap.set(key, value);
		},
		delete: (key) => cookieMap.delete(key)
	};
	const redirectLocation = async (fn) => {
		try {
			await fn();
			assert.fail('Expected redirect');
		} catch (e) {
			assert.equal(e.status, 303);
			return String(e.location);
		}
	};
	for (const [verification, expected] of [
		[{ data: { user: null, session: null }, error: null }, 'pending'],
		[
			{
				data: {
					user: { ...user, email: 'new@example.test' },
					session: { access_token: 'fixture' }
				},
				error: null
			},
			'complete'
		],
		[{ data: { user: null, session: null }, error: { message: 'expired' } }, 'error']
	]) {
		assert.equal(
			await redirectLocation(() =>
				GET({
					url: new URL(
						'https://portal.example.test/auth/confirm?type=email_change&token_hash=fixture&next=https://evil.example'
					),
					cookies,
					locals: { supabase: { auth: { verifyOtp: async () => verification } } }
				})
			),
			'/auth/email-change'
		);
		const landing = await load({
			url: new URL('https://portal.example.test/auth/email-change'),
			cookies,
			locals,
			setHeaders: () => {}
		});
		assert.equal(landing.result, expected);
		assert.equal(cookieMap.size, 0);
	}
	const plain = await load({
		url: new URL('https://portal.example.test/auth/email-change?result=complete&message=success'),
		cookies,
		locals,
		setHeaders: () => {}
	});
	assert.equal(plain.result, 'instructions');
	assert.equal(
		guardRedirect({
			pathname: '/auth/email-change',
			search: '',
			hasSession: true,
			isAnonymous: false,
			aal: locals.aal
		}),
		null
	);
	const recovery = await redirectLocation(() =>
		GET({
			url: new URL(
				'https://portal.example.test/auth/confirm?type=recovery&token_hash=secret&next=/auth/reset-password'
			),
			cookies,
			locals: {
				supabase: {
					auth: { verifyOtp: async () => ({ data: { user, session: {} }, error: null }) }
				}
			}
		})
	);
	assert.equal(recovery, 'https://portal.example.test/auth/reset-password');
	assert.ok(!recovery.includes('secret'));
	const callbackLocals = {
		...locals,
		supabase: {
			auth: {
				exchangeCodeForSession: async (code) => {
					assert.equal(code, 'auth-code');
					return { data: { user: { ...user, new_email: '' } }, error: null };
				}
			}
		}
	};
	assert.equal(
		await redirectLocation(() =>
			load({
				url: new URL('https://portal.example.test/auth/email-change?code=auth-code'),
				cookies,
				locals: callbackLocals,
				setHeaders: () => {}
			})
		),
		'/auth/email-change'
	);
	assert.equal(
		(
			await load({
				url: new URL('https://portal.example.test/auth/email-change'),
				cookies,
				locals,
				setHeaders: () => {}
			})
		).result,
		'complete'
	);
	assert.equal(
		await redirectLocation(() =>
			load({
				url: new URL('https://portal.example.test/auth/email-change?error=access_denied'),
				cookies,
				locals,
				setHeaders: () => {}
			})
		),
		'/auth/email-change'
	);
	assert.equal(
		(
			await load({
				url: new URL('https://portal.example.test/auth/email-change'),
				cookies,
				locals,
				setHeaders: () => {}
			})
		).result,
		'error'
	);

	console.log(
		'Email-change checks passed: access/MFA guards, validation, pending state, resend address, errors, first/final confirmation, and recovery compatibility.'
	);
} finally {
	await server.close();
}
