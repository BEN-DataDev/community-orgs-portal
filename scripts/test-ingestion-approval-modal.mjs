import assert from 'node:assert/strict';
import { createServer } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const approval = {
	id: '00000000-0000-4000-8000-000000000003',
	organisation_id: null,
	review_revision: 1,
	approved_at: '2026-09-17T00:00:00Z',
	published_at: null,
	published_organisation: null,
	fields: [{ field: 'pbi', current_value: null, source_value: false, revision: '0' }]
};
// Exercise the real modal in isolation. Only SvelteKit navigation/form transport
// is stubbed; no database or publication request is made.
const harness = `<script>
 import SavedApprovals from '/src/components/ingestion/SavedApprovals.svelte';
 let approvals = $state([${JSON.stringify(approval)}]);
 let savedApprovalId = $state(null);
 let message = $state(null);
 window.saved = () => { savedApprovalId = approvals[0].id; message = 'Field approval saved.'; };
 window.failed = () => { message = 'Approval not saved.'; };
 window.published = () => { approvals = approvals.map(a=>({...a,published_at:'2026-09-17T01:00:00Z',published_organisation:'00000000-0000-4000-8000-000000000001'})); message='Approved fields published.'; };
 </script>
 <button onclick={() => window.saved()}>Save field approval</button>
 <SavedApprovals {approvals} {savedApprovalId} {message} />`;
const server = await createServer({
	configFile: false,
	plugins: [
		{
			name: 'approval-harness',
			resolveId(id) {
				if (['/ApprovalHarness.svelte', '$app/forms', '$app/paths'].includes(id)) return id;
			},
			load(id) {
				if (id === '/ApprovalHarness.svelte') return harness;
				if (id === '$app/paths')
					return `export function resolve(path, params) { return path.replace('[id]',params.id); }`;
				if (id === '$app/forms')
					return `export function enhance(form) { const submit = e => { e.preventDefault(); window.submitted = Object.fromEntries(new FormData(form)); }; form.addEventListener('submit', submit); return {destroy(){form.removeEventListener('submit',submit);}}; }`;
			}
		},
		svelte({ configFile: false })
	],
	server: { host: '127.0.0.1', port: 0 },
	appType: 'custom'
});
server.middlewares.use('/modal-test', async (_req, res, next) => {
	try {
		res.setHeader('content-type', 'text/html');
		res.end(
			await server.transformIndexHtml(
				'/modal-test',
				`<!doctype html><html><body><div id="app"></div><script type="module">import {mount} from 'svelte'; import Harness from '/ApprovalHarness.svelte'; mount(Harness,{target:document.getElementById('app')});</script></body></html>`
			)
		);
	} catch (e) {
		next(e);
	}
});
let browser;
try {
	await server.listen();
	browser = await chromium.launch({ headless: true });
	const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
	const errors = [];
	page.on('pageerror', (e) => errors.push(e.message));
	await page.goto(`http://127.0.0.1:${server.httpServer.address().port}/modal-test`);
	const saved = page.getByRole('button', { name: 'Save field approval', exact: true });
	await saved.waitFor();
	const dialog = page.getByRole('dialog', { name: 'Saved field approvals' });
	assert.equal(await dialog.count(), 0);
	await page.evaluate(() => window.failed());
	assert.equal(await page.locator('dialog').evaluate((d) => d.open), false);
	await saved.click();
	await dialog.waitFor();
	assert.equal(await page.locator('dialog').evaluate((d) => d.matches(':modal')), true);
	assert.match(await dialog.innerText(), /pbi: — → false/);
	assert.equal(await page.evaluate(() => window.submitted), undefined);
	await page.keyboard.press('Escape');
	assert.equal(await page.locator('dialog').evaluate((d) => d.open), false);
	assert.equal(await saved.evaluate((b) => b === document.activeElement), true);
	const reopen = page.getByRole('button', { name: 'View saved field approvals (1)' });
	await reopen.click();
	await dialog.waitFor();
	await dialog.getByRole('button', { name: 'Publish these approved fields' }).click();
	assert.deepEqual(await page.evaluate(() => window.submitted), {
		intent: 'publish',
		approval: approval.id
	});
	await page.evaluate(() => window.failed());
	await page.getByRole('status').filter({ hasText: 'Approval not saved.' }).waitFor();
	assert.equal(await page.locator('dialog').evaluate((d) => d.open), true);
	await page.evaluate(() => window.published());
	await dialog.getByRole('link', { name: 'View organisation' }).waitFor();
	assert.equal(
		await dialog.getByRole('button', { name: 'Publish these approved fields' }).count(),
		0
	);
	await dialog.getByRole('button', { name: 'Close', exact: true }).click();
	assert.equal(await page.locator('dialog').evaluate((d) => d.open), false);
	assert.equal(await reopen.evaluate((b) => b === document.activeElement), true);
	assert.deepEqual(errors, []);
	console.log(
		'Approval modal: successful-save opening, failure handling, Escape/focus return, reopening, explicit publication and published state passed.'
	);
} finally {
	await browser?.close();
	await server.close();
}
