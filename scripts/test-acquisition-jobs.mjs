import assert from 'node:assert/strict';
import { createServer } from 'vite';
const server = await createServer({
	optimizeDeps: { noDiscovery: true, include: [] },
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
try {
	const { load, actions } = await server.ssrLoadModule(
		'/src/routes/admin/ingestion/jobs/+page.server.ts'
	);
	let operator = false,
		admin = false,
		rpcError = null;
	const writes = [];
	const resource = '00000000-0000-4000-8000-000000000090';
	const locals = {
		user: { id: 'operator' },
		supabase: {
			rpc: async (name, args) => {
				if (name === 'is_ingestion_operator') return { data: operator };
				if (name === 'is_platform_admin') return { data: admin };
				if (name === 'acquisition_dashboard')
					return { data: { portal_scope_revision_id: '1', sources: [], jobs: [] } };
				writes.push({ name, args });
				return { data: 'job', error: rpcError };
			}
		}
	};
	const headers = {};
	const event = { locals, setHeaders: (h) => Object.assign(headers, h) };
	const submit = (action, values) =>
		actions[action]({
			...event,
			request: new Request('http://localhost/admin/ingestion/jobs', {
				method: 'POST',
				body: new URLSearchParams(values)
			})
		});
	await assert.rejects(
		() => load(event),
		(e) => e.status === 403
	);
	await assert.rejects(
		() => submit('run', { resource }),
		(e) => e.status === 403
	);
	operator = true;
	assert.equal((await load(event)).canConfigure, false);
	assert.equal(headers['cache-control'], 'private, no-store');
	await assert.rejects(
		() => submit('configure', { resource }),
		(e) => e.status === 403
	);
	assert.equal((await submit('run', { resource: 'invalid' })).status, 400);
	assert.equal(writes.length, 0);
	assert.match((await submit('run', { resource })).message, /queued/);
	rpcError = { code: '55000' };
	assert.equal((await submit('run', { resource })).status, 409);
	rpcError = null;
	admin = true;
	const values = {
		resource,
		postcodes: '2730\n2720',
		licence: 'Reviewed licence',
		interval: 'off',
		revision: '0'
	};
	assert.equal((await submit('configure', { ...values, postcodes: '273' })).status, 400);
	assert.equal((await submit('configure', { ...values, postcodes: '2730, 2730' })).status, 400);
	assert.equal((await submit('configure', { ...values, interval: '1' })).status, 400);
	assert.match((await submit('configure', values)).message, /saved/);
	assert.equal(writes.at(-1).args.p_interval, null);
	assert.deepEqual(writes.at(-1).args.p_postcodes, ['2720', '2730']);
	assert.equal(writes.at(-1).args.p_scope_exception_reason, null);
	rpcError = { code: '40001' };
	assert.equal((await submit('configure', values)).status, 409);
	const { render } = await server.ssrLoadModule('svelte/server');
	const { default: Page } = await server.ssrLoadModule(
		'/src/routes/admin/ingestion/jobs/+page.svelte'
	);
	const fixture = {
		canConfigure: true,
		portal_scope_revision_id: '1',
		sources: [
			{
				resource_id: resource,
				title: 'ACNC fixture',
				enabled: true,
				postcodes: ['2720', '2730'],
				licence_title: 'Reviewed licence',
				interval_hours: null,
				next_due_at: null,
				revision: '1',
				scope_revision_id: '1',
				scope_alignment: 'exact',
				scope_exception_reason: null
			}
		],
		jobs: [
			{
				id: 'fixture-job',
				resource_id: resource,
				status: 'complete',
				origin: 'manual',
				attempts: 1,
				created_at: '2026-09-17T00:00:00Z',
				available_at: '2026-09-17T00:00:00Z',
				lease_until: null,
				finished_at: '2026-09-17T00:01:00Z',
				run_id: '33',
				message: 'Ready for review.',
				acquired: true
			}
		]
	};
	const html = render(Page, { props: { data: fixture, form: null } }).body;
	assert.match(html, /Run acquisition/);
	assert.match(html, /run=33/);
	assert.match(html, /Ready for review/);
	const operatorHtml = render(Page, {
		props: { data: { ...fixture, canConfigure: false }, form: null }
	}).body;
	assert.doesNotMatch(operatorHtml, /Save configuration/);
	if (process.env.PLAYWRIGHT_MODULE) {
		const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
		const browser = await chromium.launch({ headless: true });
		try {
			const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
			await page.setContent(html);
			assert.ok(await page.getByRole('button', { name: 'Run acquisition' }).isEnabled());
			await page.getByText('Configure acquisition', { exact: true }).click();
			assert.equal(
				await page.getByLabel('Postcodes (one per line)', { exact: true }).inputValue(),
				'2720\n2730'
			);
			assert.equal(await page.getByRole('combobox', { name: /Schedule/ }).inputValue(), 'off');
			await page.getByLabel('Postcodes (one per line)', { exact: true }).fill('273');
			assert.equal(
				await page.getByRole('link', { name: 'Review import' }).getAttribute('href'),
				'/admin/ingestion?run=33'
			);
			await page.setContent(
				render(Page, {
					props: {
						data: { ...fixture, sources: [{ ...fixture.sources[0], enabled: false }] },
						form: null
					}
				}).body
			);
			assert.ok(await page.getByRole('button', { name: 'Run acquisition' }).isDisabled());
		} finally {
			await browser.close();
		}
	}
	console.log(
		'Acquisition routes: permissions, validation, private caching, disabled schedule and stale configuration passed.'
	);
} finally {
	await server.close();
}
