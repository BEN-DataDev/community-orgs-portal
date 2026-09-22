// Local browser integration: real page/form/picker and server action; synthetic
// Supabase transport/storage and a small enhance adapter replace hosted services/router.
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { createServer } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const current = {
	org_id: 'a1111111-1111-4111-8111-111111111111',
	entity_name: 'Community Current'
};
const partner = {
	org_id: 'b2222222-2222-4222-8222-222222222222',
	entity_name: 'Community Partner'
};
const relationships = [];
const searches = [];
let editor = true;
const backend = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
const { actions } = await backend.ssrLoadModule(
	'/src/routes/organisations/[id]/relationships/+page.server.ts'
);
const locals = {
	user: { id: 'c3333333-3333-4333-8333-333333333333' },
	supabase: {
		async rpc(name, args) {
			assert.equal(name, 'user_max_role_level');
			assert.equal(args.p_organisation_id, current.org_id);
			return { data: editor ? 3 : 0, error: null };
		},
		from(table) {
			assert.equal(table, 'relationships');
			return {
				async insert(row) {
					assert.equal(row.org_id, current.org_id);
					relationships.push({ ...row, relationship_id: String(relationships.length + 1) });
					return { error: null };
				}
			};
		}
	}
};
const forms = `export function enhance(form, submit) {
 const handler = async (event) => {
  event.preventDefault();
  const callback = submit();
  const response = await fetch(form.action, {method:'POST', body:new URLSearchParams(new FormData(form))});
  const data = await response.json();
  await callback({result:{type:response.ok?'success':'failure',data}, update:async()=>{if(response.ok)location.reload();}});
 };
 form.addEventListener('submit',handler);
 return {destroy(){form.removeEventListener('submit',handler);}};
}`;
const server = await createServer({
	configFile: false,
	plugins: [
		{
			name: 'test-forms',
			resolveId(id) {
				if (id === '$app/forms') return '\0test-forms';
			},
			load(id) {
				if (id === '\0test-forms') return forms;
			}
		},
		svelte({ configFile: false })
	],
	resolve: { alias: { $lib: resolve('src/lib'), $components: resolve('src/components') } },
	server: { host: '127.0.0.1', port: 0 },
	appType: 'custom'
});
server.middlewares.use(async (req, res, next) => {
	try {
		const url = new URL(req.url, 'http://localhost');
		if (url.pathname === '/fixture') {
			res.setHeader('content-type', 'application/json');
			res.setHeader('cache-control', 'no-store');
			res.end(JSON.stringify(relationships));
			return;
		}
		if (url.pathname === '/search') {
			const term = url.searchParams.get('term');
			const excluded = url.searchParams.get('excluded');
			searches.push({ term, excluded });
			assert.equal(excluded, `(${current.org_id})`);
			if (term === '%slow%') await new Promise((r) => setTimeout(r, 800));
			res.setHeader('content-type', 'application/json');
			res.end(
				JSON.stringify(
					term === '%failure%'
						? { data: null, error: { message: 'Fixture failure' } }
						: {
								data:
									term === '%empty%'
										? []
										: [current, partner].filter((org) => !excluded.includes(org.org_id)),
								error: null
							}
				)
			);
			return;
		}
		if (url.pathname !== '/test') return next();
		if (req.method === 'POST') {
			let body = '';
			for await (const chunk of req) body += chunk;
			const result = await actions.createRelationship({
				locals,
				params: { id: current.org_id },
				request: new Request(url, { method: 'POST', body: new URLSearchParams(body) })
			});
			res.setHeader('content-type', 'application/json');
			res.statusCode = result.status ?? 200;
			res.end(JSON.stringify(result.data ?? result));
			return;
		}
		res.setHeader('content-type', 'text/html');
		res.end(
			await server.transformIndexHtml(
				'/test',
				`<!doctype html><html><body><div id="app"></div><script type="module">
import { mount } from 'svelte';
import Page from '/src/routes/organisations/[id]/relationships/+page.svelte';
const supabase = { from(table) {
 if(table !== 'organisations') throw Error('Unexpected table');
 let term, excluded;
 return {select(){return this},ilike(column,value){term=value;return this},limit(){return this},not(column,operator,value){excluded=value;return this},then(resolve,reject){
 if(term === '%throw%') return Promise.reject(Error('Network failure')).then(resolve,reject);
 return fetch('/search?'+new URLSearchParams({term,excluded})).then(r=>r.json()).then(resolve,reject);
 }};
}};
mount(Page,{target:document.getElementById('app'),props:{data:{organisation:${JSON.stringify(current)},relationships:await fetch('/fixture').then(r=>r.json()),supabase,roleLevel:3}}});
</script></body></html>`
			)
		);
	} catch (error) {
		next(error);
	}
});
let browser;
try {
	await server.listen();
	browser = await chromium.launch({ headless: true });
	const page = await browser.newPage();
	const errors = [];
	page.on('pageerror', (error) => errors.push(error.message));
	await page.goto(`http://127.0.0.1:${server.httpServer.address().port}/test`);
	await page.getByRole('button', { name: 'Add Relationship' }).click();
	const input = page.getByLabel('Partner Organisation', { exact: true });
	const create = page.getByRole('button', { name: 'Create Relationship', exact: true });
	await input.fill('Community');
	await page.getByRole('button', { name: partner.entity_name, exact: true }).waitFor();
	assert.equal(
		await page.getByRole('button', { name: current.entity_name, exact: true }).count(),
		0
	);
	await page.getByRole('button', { name: partner.entity_name, exact: true }).click();
	assert.equal(await create.isEnabled(), true);
	await input.fill('failure');
	assert.equal(await create.isDisabled(), true);
	assert.equal(await page.locator('input[name=partner_org]').inputValue(), '');
	await page.getByRole('alert').waitFor();
	assert.match(await page.getByRole('alert').innerText(), /Could not search/);
	assert.equal(
		await page.getByRole('button', { name: partner.entity_name, exact: true }).count(),
		0
	);
	await input.fill('throw');
	await page.getByRole('alert').waitFor();
	await input.fill('empty');
	await page.getByRole('status').waitFor();
	assert.equal(await page.getByRole('status').innerText(), 'No organisations found.');
	await input.fill('slow');
	await page.waitForRequest((request) => request.url().includes('term=%25slow%25'));
	await input.fill('x');
	await page.waitForTimeout(1000);
	assert.equal(
		await page.getByRole('button', { name: partner.entity_name, exact: true }).count(),
		0
	);
	await input.fill('Community');
	await page.getByRole('button', { name: partner.entity_name, exact: true }).click();
	await page.getByLabel('Relationship Type', { exact: true }).selectOption('Partnership');
	await page.getByLabel('Start Date', { exact: true }).fill('2026-09-17');
	const submission = page.waitForResponse((response) => response.request().method() === 'POST');
	await create.click();
	const response = await submission;
	assert.equal(response.status(), 200);
	assert.equal(relationships.length, 1);
	await page.getByRole('heading', { name: partner.entity_name, exact: true }).waitFor();
	assert.equal(relationships.length, 1);
	assert.equal(relationships[0].partner_org, partner.entity_name);
	assert.equal(relationships[0].relationship_type, 'Partnership');
	assert.equal(relationships[0].start_date, '2026-09-17');
	assert.ok(searches.length >= 5);
	assert.deepEqual(errors, []);
	editor = false;
	await assert.rejects(
		() =>
			actions.createRelationship({
				locals,
				params: { id: current.org_id },
				request: new Request('http://localhost/test', {
					method: 'POST',
					body: new URLSearchParams()
				})
			}),
		(error) => error.status === 403
	);
	assert.equal(relationships.length, 1);
	console.log(
		'Relationship browser integration passed: UUID exclusion, failures, empty/stale results, selection reset, creation and editor authorization.'
	);
} finally {
	await browser?.close();
	await server.close();
	await backend.close();
}
