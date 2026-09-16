// Uses synthetic results exported under SET ROLE anon by public_register_facts.sql.
// Real page loaders and Svelte SSR run against those results; no hosted credentials.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createServer } from 'vite';
const fixture = JSON.parse(
	await readFile(process.env.REGISTER_PAGE_FIXTURE || '/tmp/f04-browser.json', 'utf8')
);
const server = await createServer({
	optimizeDeps: { noDiscovery: true, include: [] },
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
try {
	const { render } = await server.ssrLoadModule('svelte/server');
	const { registerFactsSchema, safePublicUrl, factValue } = await server.ssrLoadModule(
		'/src/lib/register-facts.ts'
	);
	for (const bad of [
		'javascript:alert(1)',
		'data:text/html,test',
		'https://user:pass@example.org',
		'https://exa mple.org'
	])
		assert.equal(safePublicUrl(bad), null);
	assert.equal(
		factValue({
			...fixture.public.facts.find((f) => f.field === 'responsible_person_count'),
			value: 0
		}),
		'0'
	);
	const seen = new Set();
	const pages = [];
	for (const section of ['', 'contact', 'legal', 'operations', 'finance']) {
		const base = '/src/routes/organisations/[id]/' + (section ? section + '/' : '');
		const { load } = await server.ssrLoadModule(base + '+page.server.ts');
		const { default: Page } = await server.ssrLoadModule(base + '+page.svelte');
		for (const scenario of ['public', 'suppressed', 'withdrawn']) {
			const data = fixture[scenario];
			const client = {
				from(table) {
					const rows = table === 'organisations' ? data.organisation : null;
					const result = { data: rows, error: null };
					return {
						select() {
							return this;
						},
						eq() {
							return this;
						},
						order() {
							return Promise.resolve(result);
						},
						maybeSingle() {
							return Promise.resolve(result);
						},
						then(resolve, reject) {
							return Promise.resolve(result).then(resolve, reject);
						}
					};
				},
				async rpc(name) {
					assert.equal(name, 'organisation_register_facts');
					return { data: data.facts, error: null };
				}
			};
			const event = {
				locals: { supabase: client, user: null },
				params: { id: fixture.public.organisation.org_id },
				setHeaders(headers) {
					assert.equal(headers['cache-control'], 'private, no-store');
				}
			};
			if (scenario === 'withdrawn') {
				await assert.rejects(
					() => load(event),
					(err) => err.status === 404
				);
				continue;
			}
			const pageData = await load(event);
			assert.equal(pageData.roleLevel, 0);
			assert.deepEqual(pageData.registerFacts, registerFactsSchema.parse(data.facts));
			const html = render(Page, { props: { data: pageData, form: null } }).body.replace(
				/\s+/g,
				' '
			);
			assert.doesNotMatch(
				html,
				/PRIVATE_SENTINEL|PRIVATE_SUPPRESSION_REASON|RAW_PRIVATE|source_record_id|source_version|reviewed_by/
			);
			assert.doesNotMatch(html, />Edit (Details|Contact Info|Legal|Financial|Operations)/);
			if (scenario === 'public') {
				for (const [, key] of html.matchAll(/data-register-field="([^"]+)"/g)) seen.add(key);
				if (section === 'legal') {
					assert.match(html, /Public Benevolent Institution/);
					assert.match(html, />Yes</);
					assert.match(html, />No</);
					assert.equal([...html.matchAll(/data-register-field="pbi"/g)].length, 2);
					assert.match(html, /Source-reported date/);
				}
				if (section === 'contact') {
					assert.match(html, /Synthetic Address Line 3/);
					assert.match(html, /0800/);
					assert.match(html, /not necessarily a service location/);
				}
				if (section === 'finance') {
					assert.match(html, /30 June/);
					assert.match(html, /reporting calendar/);
				}
				if (section === 'operations') {
					assert.match(html, /Charitable purposes/);
					assert.match(html, /Beneficiaries/);
					assert.match(html, /unknown or not published/);
				}
				if (section === '') {
					assert.match(html, /Governance summary/);
					assert.match(html, /Unclassified; name,/);
				}
				assert.match(html, /Observed/);
				assert.match(html, /href="https:\/\/example.org\/register"/);
			} else assert.doesNotMatch(html, /data-register-field="pbi"/);
			pages.push({ path: `/${scenario}/${section}`, html });
		}
		// Fail closed if public fact retrieval fails rather than silently showing an empty section.
		const failed = {
			locals: {
				supabase: {
					from() {
						return {
							select() {
								return this;
							},
							eq() {
								return this;
							},
							order() {
								return Promise.resolve({ data: [], error: null });
							},
							maybeSingle() {
								return Promise.resolve({ data: fixture.public.organisation, error: null });
							},
							then(resolve) {
								resolve({ data: [], error: null });
							}
						};
					},
					rpc: async () => ({ data: null, error: { message: 'failed' } })
				},
				user: null
			},
			params: { id: fixture.public.organisation.org_id },
			setHeaders() {}
		};
		await assert.rejects(
			() => load(failed),
			(err) => err.status === 500
		);
	}
	assert.equal(seen.size, 62);
	if (process.env.PLAYWRIGHT_MODULE) {
		const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
		const browser = await chromium.launch({ headless: true });
		try {
			const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
			for (const entry of pages) {
				await page.setContent(entry.html);
				assert.ok(await page.getByRole('heading', { level: 1 }).isVisible(), entry.path);
				for (const heading of await page
					.locator('section[aria-label$="register details"] h2')
					.all())
					assert.ok(await heading.isVisible());
				assert.equal(await page.locator('a[href^="javascript:"]').count(), 0);
			}
		} finally {
			await browser.close();
		}
	}
	console.log(
		'Anonymous page loaders and SSR: all 62 review units on five pages, disagreements, source dates/links, suppression, withdrawal 404s and fail-closed retrieval passed.'
	);
} finally {
	await server.close();
}
