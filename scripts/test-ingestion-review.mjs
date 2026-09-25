import assert from 'node:assert/strict';
import { createServer } from 'vite';

const server = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});

try {
	const identity = await server.ssrLoadModule(
		'/src/routes/admin/ingestion/identity/+page.server.ts'
	);
	const changes = await server.ssrLoadModule('/src/routes/admin/ingestion/changes/+page.server.ts');
	const suppressions = await server.ssrLoadModule(
		'/src/routes/admin/ingestion/suppressions/+page.server.ts'
	);
	let operator = false;
	let rpcError = null;
	let previewError = null;
	const calls = [];
	const matchedOrg = '00000000-0000-4000-8000-000000001411';
	const approvalId = '00000000-0000-4000-8000-000000000003';
	const releaseId = '00000000-0000-4000-8000-000000000004';
	const preview = { organisation_id: null, organisation_name: null, fields: [] };
	const queue = { runs: [], run: null, total: 0, records: [], detail: null, candidates: [] };
	const database = {
		rpc: async (name, args) => {
			calls.push([name, args]);
			if (name === 'is_data_steward') return { data: operator, error: null };
			if (name === 'ingestion_review_queue') return { data: queue, error: rpcError };
			if (name === 'ingestion_field_preview') return { data: preview, error: previewError };
			if (name === 'ingestion_field_approvals') return { data: [], error: rpcError };
			if (name === 'ingestion_withdrawal_status')
				return { data: { organisation_id: null, suppressions: [] }, error: rpcError };
			if (name === 'approve_ingestion_fields') return { data: approvalId, error: rpcError };
			if (name === 'submit_publication_release') return { data: releaseId, error: rpcError };
			return { data: null, error: rpcError };
		}
	};
	const locals = { providers: { database } };
	const event = (path = '/admin/ingestion/identity') => ({
		locals,
		url: new URL(`http://localhost${path}`),
		setHeaders: () => {}
	});
	const submit = (action, values, path) =>
		action({
			locals,
			request: new Request(`http://localhost${path}`, {
				method: 'POST',
				body: values instanceof URLSearchParams ? values : new URLSearchParams(values)
			})
		});

	await assert.rejects(
		() => identity.load(event()),
		(error) => error.status === 403
	);
	operator = true;
	assert.equal((await identity.load(event())).queue.total, 0);
	await assert.rejects(
		() => identity.load(event('/admin/ingestion/identity?offset=-1')),
		(error) => error.status === 400
	);
	queue.run = '1';
	queue.detail = {
		id: '2',
		native_id: 'fixture',
		payload: { assertions: [] },
		review: null,
		identity_match: { status: 'match', organisation_id: matchedOrg, reason: 'Verified exact ABN' }
	};
	assert.equal(
		(await identity.load(event())).queue.detail.identity_match.organisation_id,
		matchedOrg
	);

	const identityValues = {
		run: '1',
		version: '2',
		revision: '0',
		decision: 'link',
		organisation: '',
		note: 'Checked'
	};
	assert.equal(
		(await submit(identity.actions.default, identityValues, '/admin/ingestion/identity')).status,
		400
	);
	assert.equal(
		calls.some(([name]) => name === 'save_ingestion_review'),
		false
	);
	identityValues.decision = 'defer';
	assert.match(
		(await submit(identity.actions.default, identityValues, '/admin/ingestion/identity')).message,
		/decision saved/i
	);
	assert.equal(calls.at(-1)[0], 'save_ingestion_review');
	rpcError = { code: '40001', message: 'stale' };
	assert.equal(
		(await submit(identity.actions.default, identityValues, '/admin/ingestion/identity')).status,
		409
	);
	rpcError = null;

	const loadedChanges = await changes.load(event('/admin/ingestion/changes?run=1&version=2'));
	assert.equal(loadedChanges.preview.organisation_id, null);
	assert.equal(
		calls.findLast(([name]) => name === 'ingestion_field_preview')[1].p_organisation,
		matchedOrg
	);
	await changes.load(event('/admin/ingestion/changes?run=1&version=2&target='));
	assert.equal(
		calls.findLast(([name]) => name === 'ingestion_field_preview')[1].p_organisation,
		undefined
	);
	await assert.rejects(
		() => changes.load(event('/admin/ingestion/changes?run=1&version=2&target=invalid')),
		(error) => error.status === 400
	);
	previewError = { code: '42501', message: 'denied' };
	await assert.rejects(
		() => changes.load(event('/admin/ingestion/changes?run=1&version=2')),
		(error) => error.status === 403
	);
	previewError = null;

	const field = {
		field: 'website',
		section: 'Contact',
		label: 'Website',
		atomic_group: false,
		input_value: 'https://example.org',
		record_id: '0',
		projection_public: null,
		source_token: 'source-state',
		mapping_token: 'mapping-state',
		source_version: '2',
		mapping_version: 'acnc-register-fields-v2',
		source_values: { Charity_Website: 'https://example.org' },
		table: 'contact_info',
		source_value: 'https://example.org',
		current_value: null,
		status: 'new',
		protected: false,
		revision: '0',
		target_rows: 0,
		changed_at: null
	};
	const approvalForm = {
		intent: 'approve',
		run: '1',
		version: '2',
		revision: '1',
		organisation: matchedOrg,
		field: JSON.stringify(field)
	};
	assert.equal(
		(
			await submit(
				changes.actions.default,
				{ intent: 'approve', field: '{' },
				'/admin/ingestion/changes'
			)
		).status,
		400
	);
	const approval = await submit(changes.actions.default, approvalForm, '/admin/ingestion/changes');
	assert.equal(approval.approvalId, approvalId);
	assert.match(approval.message, /approval saved/i);
	assert.deepEqual(calls.at(-1)[1].p_fields, [field]);
	const multiple = new URLSearchParams(approvalForm);
	for (const key of ['pbi', 'hpc', 'charity_size'])
		multiple.append('field', JSON.stringify({ ...field, field: key }));
	await submit(changes.actions.default, multiple, '/admin/ingestion/changes');
	assert.equal(calls.at(-1)[1].p_fields.length, 4);

	const releaseForm = {
		intent: 'submit_publication',
		approval: approvalId,
		releaseClass: 'ordinary_update',
		reason: 'Synthetic release'
	};
	const released = await submit(changes.actions.default, releaseForm, '/admin/ingestion/changes');
	assert.equal(released.releaseId, releaseId);
	assert.match(released.message, /release submitted/i);
	rpcError = { code: '40001', message: 'stale' };
	assert.equal(
		(await submit(changes.actions.default, releaseForm, '/admin/ingestion/changes')).status,
		409
	);
	rpcError = { code: '22023', message: 'Complete enabled source required' };
	const paused = await submit(changes.actions.default, approvalForm, '/admin/ingestion/changes');
	assert.match(paused.data.message, /source is paused/);

	rpcError = null;
	const suppressionForm = {
		run: '1',
		version: '2',
		field: '*',
		reason: 'Synthetic withdrawal',
		expected: JSON.stringify({ organisation_id: null }),
		confirmed: 'yes'
	};
	assert.equal(
		(
			await submit(
				suppressions.actions.default,
				{ ...suppressionForm, confirmed: '' },
				'/admin/ingestion/suppressions'
			)
		).status,
		400
	);
	const suppressed = await submit(
		suppressions.actions.default,
		suppressionForm,
		'/admin/ingestion/suppressions'
	);
	assert.equal(suppressed.releaseId, releaseId);
	assert.match(suppressed.message, /Suppression release submitted/);

	operator = false;
	for (const route of [identity, changes, suppressions]) {
		await assert.rejects(
			() => route.load(event()),
			(error) => error.status === 403
		);
	}
	console.log(
		'Focused identity, field-change and suppression route authorization, validation, previews and release submission checks passed.'
	);
} finally {
	await server.close();
}
