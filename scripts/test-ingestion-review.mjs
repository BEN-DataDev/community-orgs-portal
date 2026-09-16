import assert from 'node:assert/strict';
import { createServer } from 'vite';
const server = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
try {
	const { load, actions } = await server.ssrLoadModule(
		'/src/routes/admin/ingestion/+page.server.ts'
	);
	let operator = false,
		saveError = null,
		calls = [];
	let previewError = null;
	const preview = { organisation_id: null, organisation_name: null, fields: [] };
	const queue = { runs: [], run: null, total: 0, records: [], detail: null, candidates: [] };
	const locals = {
		supabase: {
			rpc: async (name, args) => {
				calls.push([name, args]);
				if (name === 'ingestion_withdrawal_status')
					return { data: { organisation_id: null, suppressions: [] }, error: null };
				if (name === 'ingestion_field_approvals') return { data: [], error: null };
				if (name === 'ingestion_field_preview') return { data: preview, error: previewError };
				return name === 'is_ingestion_operator'
					? { data: operator, error: null }
					: name === 'ingestion_review_queue'
						? { data: queue, error: null }
						: { error: saveError };
			}
		}
	};
	const event = { locals, url: new URL('http://localhost/admin/ingestion'), setHeaders: () => {} };
	await assert.rejects(
		() => load(event),
		(e) => e.status === 403
	);
	operator = true;
	assert.equal((await load(event)).queue.total, 0);
	await assert.rejects(
		() => load({ ...event, url: new URL('http://localhost/admin/ingestion?offset=-1') }),
		(e) => e.status === 400
	);
	const values = {
		run: '1',
		version: '2',
		revision: '0',
		decision: 'link',
		organisation: '',
		note: 'Checked'
	};
	const submit = () =>
		actions.default({
			locals,
			request: new Request('http://localhost/admin/ingestion', {
				method: 'POST',
				body: new URLSearchParams(values)
			})
		});
	assert.equal((await submit()).status, 400);
	assert.equal(
		calls.some(([name]) => name === 'save_ingestion_review'),
		false
	);
	values.decision = 'defer';
	assert.match((await submit()).message, /Review saved/);
	saveError = { code: '40001' };
	assert.equal((await submit()).status, 409);
	queue.run = '1';
	queue.detail = {
		id: '2',
		native_id: 'source-1',
		payload: { assertions: [] },
		review: {
			revision: 1,
			decision: 'link',
			organisation_id: '00000000-0000-4000-8000-000000000001',
			note: 'Scope checked',
			reviewed_at: '2026-09-16T00:00:00Z'
		}
	};
	await load(event);
	assert.equal(
		calls.findLast(([name]) => name === 'ingestion_field_preview')[1].p_organisation,
		queue.detail.review.organisation_id
	);
	await load({ ...event, url: new URL('http://localhost/admin/ingestion?target=') });
	assert.equal(
		calls.findLast(([name]) => name === 'ingestion_field_preview')[1].p_organisation,
		undefined
	);
	await assert.rejects(
		() => load({ ...event, url: new URL('http://localhost/admin/ingestion?target=invalid') }),
		(e) => e.status === 400
	);
	previewError = { code: 'P0002' };
	await assert.rejects(
		() => load(event),
		(e) => e.status === 404
	);
	previewError = { code: '42501' };
	await assert.rejects(
		() => load(event),
		(e) => e.status === 403
	);
	saveError = null;
	const action = (values) =>
		actions.default({
			locals,
			request: new Request('http://localhost/admin/ingestion', {
				method: 'POST',
				body: new URLSearchParams(values)
			})
		});
	assert.equal((await action({ intent: 'publish', approval: 'bad' })).status, 400);
	assert.equal((await action({ intent: 'approve', field: '{' })).status, 400);
	const field = {
		field: 'website',
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
		organisation: queue.detail.review.organisation_id,
		field: JSON.stringify(field)
	};
	assert.match((await action(approvalForm)).message, /approval saved/);
	assert.equal(calls.at(-1)[0], 'approve_ingestion_fields');
	const publishForm = { intent: 'publish', approval: '00000000-0000-4000-8000-000000000003' };
	assert.match((await action(publishForm)).message, /published/);
	saveError = { code: '40001' };
	assert.equal((await action(publishForm)).status, 409);
	assert.equal((await action(approvalForm)).status, 409);
	saveError = { code: '22023', message: 'Complete enabled source required' };
	const paused = await action(approvalForm);
	assert.equal(paused.data.intent, 'approve');
	assert.match(paused.data.message, /source is paused/);
	saveError = { code: '22023', message: 'New organisation requires name' };
	assert.match((await action(approvalForm)).data.message, /select Entity name/);

	const suppressionForm = {
		intent: 'suppress',
		run: '1',
		version: '2',
		field: '*',
		reason: 'Synthetic withdrawal',
		expected: JSON.stringify({ organisation_id: null }),
		confirmed: 'yes'
	};
	saveError = null;
	assert.equal((await action({ ...suppressionForm, confirmed: '' })).status, 400);
	assert.equal((await action({ ...suppressionForm, expected: '{' })).status, 400);
	assert.match((await action(suppressionForm)).message, /Suppression saved/);
	assert.equal(calls.at(-1)[0], 'suppress_ingestion_content');
	saveError = { code: '40001' };
	assert.equal((await action(suppressionForm)).status, 409);
	operator = false;
	await assert.rejects(
		() => action(suppressionForm),
		(e) => e.status === 403
	);
	await assert.rejects(
		() => action(publishForm),
		(e) => e.status === 403
	);
	await assert.rejects(
		() => action(approvalForm),
		(e) => e.status === 403
	);
	await assert.rejects(
		() => load(event),
		(e) => e.status === 403
	);
	await assert.rejects(submit, (e) => e.status === 403);
	console.log(
		'Review route authorization, input validation, empty queue, save, stale revision field previews, selected approvals and publication action checks passed.'
	);
} finally {
	await server.close();
}
