import assert from 'node:assert/strict';
import { createServer } from 'vite';
const server = await createServer({
	optimizeDeps: { noDiscovery: true, include: [] },
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
try {
	const route = await server.ssrLoadModule('/src/routes/organisations/[id]/access/+page.server.ts');
	const org = '00000000-0000-4000-8000-000000000811';
	const actor = '00000000-0000-4000-8000-000000000801';
	const target = '00000000-0000-4000-8000-000000000802';
	const role = '00000000-0000-4000-8000-000000000803';
	let rosterError = null,
		mutationError = null,
		mutationData = true,
		malformed = false;
	const calls = [];
	const headers = {};
	const event = {
		params: { id: org },
		setHeaders: (h) => Object.assign(headers, h),
		locals: {
			user: { id: actor },
			isAnonymous: false,
			supabase: {
				rpc: async (name, args) => {
					calls.push({ name, args });
					if (name === 'organisation_role_assignments')
						return {
							data: malformed ? {} : { name: 'Test', level: 4, roles: [], assignments: [] },
							error: rosterError
						};
					return { data: mutationData, error: mutationError };
				}
			}
		},
		request: {
			formData: async () =>
				new Map(
					Object.entries({
						userId: target,
						roleId: role,
						p_granted_by: target,
						p_organisation_id: target,
						confirm: 'yes',
						reason: 'Transfer'
					})
				)
		}
	};
	for (const method of [route.load, ...Object.values(route.actions)]) {
		for (const locals of [
			{ ...event.locals, user: null },
			{ ...event.locals, isAnonymous: true }
		]) {
			calls.length = 0;
			await assert.rejects(
				() => method({ ...event, locals }),
				(e) => e.status === 403
			);
			assert.equal(calls.length, 0);
		}
		for (const code of ['42501', 'XX000']) {
			rosterError = { code };
			calls.length = 0;
			await assert.rejects(
				() => method(event),
				(e) => e.status === (code === '42501' ? 403 : 500)
			);
			assert.deepEqual(
				calls.map((c) => c.name),
				['organisation_role_assignments']
			);
		}
		rosterError = null;
		await assert.rejects(
			() => method({ ...event, params: { id: 'bad' } }),
			(e) => e.status === 404
		);
	}
	await route.load(event);
	assert.equal(headers['cache-control'], 'private, no-store');
	malformed = true;
	await assert.rejects(
		() => route.load(event),
		(e) => e.status === 500
	);
	malformed = false;
	for (const name of ['grant', 'revoke']) {
		calls.length = 0;
		assert.equal((await route.actions[name](event)).success, true);
		const sent = calls.at(-1);
		assert.equal(sent.name, name === 'grant' ? 'grant_user_role' : 'revoke_user_role');
		assert.equal(sent.args.p_organisation_id, org);
		assert.equal(sent.args.p_user_id, target);
		assert.equal(sent.args[name === 'grant' ? 'p_granted_by' : 'p_revoked_by'], actor);
		const invalid = {
			...event,
			request: {
				formData: async () =>
					new Map([
						['userId', 'bad'],
						['roleId', role]
					])
			}
		};
		assert.equal((await route.actions[name](invalid)).status, 400);
		mutationError = { code: '42501' };
		assert.equal((await route.actions[name](event)).status, 403);
		mutationError = null;
	}
	mutationData = false;
	assert.equal((await route.actions.revoke(event)).status, 409);
	assert.equal(
		(
			await route.actions.revoke({
				...event,
				request: {
					formData: async () =>
						new Map([
							['userId', target],
							['roleId', role]
						])
				}
			})
		).status,
		400
	);
	const { default: Page } = await server.ssrLoadModule(
		'/src/routes/organisations/[id]/access/+page.svelte'
	);
	const { render } = await server.ssrLoadModule('svelte/server');
	const fixture = {
		actorId: actor,
		roster: {
			name: 'Fixture org',
			level: 4,
			roles: [{ id: role, name: 'member', level: 1 }],
			assignments: [
				{
					id: role,
					userId: target,
					roleId: role,
					role: 'member',
					level: 1,
					active: true,
					expiresAt: null,
					grantedAt: null,
					status: 'Active',
					canRevoke: true
				}
			]
		}
	};
	const html = render(Page, {
		props: { data: fixture, form: { success: true, message: 'Role granted without expiry.' } }
	}).body;
	assert.match(html, /action="\?\/grant"/);
	assert.match(html, /action="\?\/revoke"/);
	assert.match(html, /name="confirm"/);
	assert.match(html, /Role granted without expiry/);
	assert.ok(html.includes(target));
	fixture.roster.assignments[0].canRevoke = false;
	assert.doesNotMatch(
		render(Page, { props: { data: fixture, form: null } }).body,
		/action="\?\/revoke"/
	);

	console.log(
		'P08 loaders/actions: authorization, private caching, validation, caller/org identity, RPC failures and stale revocations passed.'
	);
} finally {
	await server.close();
}
