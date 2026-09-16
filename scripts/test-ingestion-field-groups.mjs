import assert from 'node:assert/strict';
import { createServer } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const field = (name, section, status = 'new', value = true) => ({
	field: name,
	section,
	label: name,
	table: 'acnc_register_details',
	atomic_group: false,
	source_value: value,
	input_value: value,
	current_value: null,
	status,
	protected: status === 'conflict',
	revision: '0',
	target_rows: 0,
	changed_at: null,
	record_id: '1',
	projection_public: null,
	source_token: 's',
	mapping_token: 'm',
	source_version: '1',
	mapping_version: 'acnc-register-fields-v2',
	source_values: { source: value }
});
const fields = [
	field('entity_name', 'Overview', 'new', 'Example'),
	field('pbi', 'Legal', 'new', false),
	field('hpc', 'Legal', 'conflict'),
	field('invalid_flag', 'Legal', 'invalid', 'N'),
	field('missing_flag', 'Legal', 'missing', null),
	{
		...field('administrative_address', 'Contact', 'changed', { line_1: 'New', line_2: 'Retained' }),
		current_value: { line_1: 'Old', line_2: 'Retained' },
		atomic_group: true
	},
	field('purposes.advancing_health', 'Operations'),
	field('beneficiaries.adults', 'Operations'),
	field('financial_year_end', 'Finance', 'new', { month: 6, day: 30 }),
	field('responsible_person_count', 'Governance', 'new', 0),
	field('future', 'Unmapped', 'unmapped')
];
const server = await createServer({
	configFile: false,
	plugins: [svelte({ configFile: false })],
	server: { host: '127.0.0.1', port: 0 },
	appType: 'custom'
});
server.middlewares.use('/f03-test', async (_req, res, next) => {
	try {
		res.setHeader('content-type', 'text/html');
		res.end(
			await server.transformIndexHtml(
				'/f03-test',
				`<!doctype html><html><body>
   <form><div id="app"></div></form><script type="module">
    import { mount } from 'svelte';
    import FieldGroups from '/src/components/ingestion/FieldGroups.svelte';
    mount(FieldGroups,{target:document.getElementById('app'),props:{fields:${JSON.stringify(fields)},selectable:true}});
   </script></body></html>`
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
	const page = await browser.newPage();
	const errors = [];
	page.on('pageerror', (e) => {
		errors.push(e.message);
		console.error(e.message);
	});
	await page.goto(`http://127.0.0.1:${server.httpServer.address().port}/f03-test`);
	await page.getByRole('checkbox', { name: 'Select all eligible in Legal' }).waitFor();
	assert.equal(await page.locator('fieldset').count(), 7);
	const legal = page.getByRole('group', { name: 'Legal fields' });
	assert.match(await legal.innerText(), /1 eligible · 1 conflicting · 1 invalid · 1 excluded/);
	await page.getByRole('checkbox', { name: 'Select all eligible in Legal' }).check();
	let selected = await page
		.locator('input[name=field]:checked')
		.evaluateAll((xs) => xs.map((x) => JSON.parse(x.value)));
	assert.deepEqual(
		selected.map((x) => x.field),
		['pbi']
	);
	assert.equal(selected[0].source_value, false);
	await page.getByRole('checkbox', { name: 'Select all eligible in Operations' }).check();
	assert.equal(await page.locator('input[name=field]:checked').count(), 3);
	await page.getByRole('checkbox', { name: 'purposes.advancing_health', exact: true }).uncheck();
	assert.equal(
		await page.getByRole('checkbox', { name: 'Select all eligible in Operations' }).isChecked(),
		false
	);
	await page.getByRole('checkbox', { name: 'Select all eligible in Legal' }).uncheck();
	assert.equal(await page.locator('input[name=field]:checked').count(), 1);
	await page.getByRole('checkbox', { name: 'administrative_address', exact: true }).check();
	selected = await page
		.locator('input[name=field]:checked')
		.evaluateAll((xs) => xs.map((x) => JSON.parse(x.value)));
	const address = selected.find((x) => x.field === 'administrative_address');
	assert.deepEqual(address.current_value, { line_1: 'Old', line_2: 'Retained' });
	assert.deepEqual(address.source_value, { line_1: 'New', line_2: 'Retained' });
	assert.equal(address.mapping_token, 'm');
	assert.equal(
		await page.getByRole('checkbox', { name: 'Select all eligible in Unmapped' }).isDisabled(),
		true
	);
	assert.deepEqual(errors, []);
	console.log(
		'Field groups: selection, exclusions, false values, atomic address diff and submitted snapshots passed.'
	);
} finally {
	await browser?.close();
	await server.close();
}
