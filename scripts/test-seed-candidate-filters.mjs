import assert from 'node:assert/strict';
import { createServer } from 'vite';

const server = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});

try {
	const { load } = await server.ssrLoadModule(
		'/src/routes/admin/ingestion/candidates/+page.server.ts'
	);
	const calls = [];
	const queue = {
		releases: [
			{
				id: '2',
				release_key: '2026-09-23',
				source_id: 'abr-bulk',
				resource_id: 'abr-public-bulk',
				observed_at: '2026-09-23T12:33:03Z',
				completion: 'complete',
				candidate_count: 157156,
				raw_removed_at: null
			}
		],
		release_id: '2',
		total: 1,
		offset: 0,
		records: [
			{
				version_id: '42',
				native_id: '51824753556',
				name: 'Included Association',
				entity_type: 'Other Incorporated Entity',
				postcode: '2730',
				has_dgr: true,
				match_strength: 'strong',
				decision: 'pending',
				revision: 0,
				in_scope: true,
				promoted: false
			}
		],
		detail: null
	};
	const database = {
		rpc: async (name, args) => {
			calls.push([name, args]);
			if (name === 'is_data_steward') return { data: true, error: null };
			if (name === 'registry_seed_triage_queue') return { data: queue, error: null };
			return { data: null, error: null };
		}
	};
	const event = (query) => ({
		locals: { providers: { database } },
		url: new URL(`http://localhost/admin/ingestion/candidates?${query}`),
		setHeaders: () => {}
	});

	const result = await load(
		event(
			'release=2&decision=pending&search=Association&entity=exclude_private_company&postcode=2730&dgr=present&match=strong'
		)
	);
	assert.equal(result.queue.total, 1);
	assert.deepEqual(result.filters, {
		search: 'Association',
		entityType: 'exclude_private_company',
		postcode: '2730',
		dgr: 'present',
		match: 'strong',
		decision: 'pending'
	});
	const args = calls.find(([name]) => name === 'registry_seed_triage_queue')[1];
	assert.equal(args.p_search, 'Association');
	assert.equal(args.p_entity_type, 'exclude_private_company');
	assert.equal(args.p_postcode, '2730');
	assert.equal(args.p_dgr, 'present');
	assert.equal(args.p_match, 'strong');

	await assert.rejects(
		() => load(event('postcode=273&entity=all&dgr=all&match=all')),
		(error) => error.status === 400
	);
	await assert.rejects(
		() => load(event('postcode=2730&entity=unknown&dgr=all&match=all')),
		(error) => error.status === 400
	);
	console.log('Registry seed candidate route filters and validation passed.');
} finally {
	await server.close();
}
