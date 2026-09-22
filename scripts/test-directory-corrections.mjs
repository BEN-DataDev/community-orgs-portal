import assert from 'node:assert/strict';
import { createServer } from 'vite';

const organisationId = 'a1111111-1111-4111-8111-111111111111';
const otherOrganisationId = 'b2222222-2222-4222-8222-222222222222';
const userId = 'c3333333-3333-4333-8333-333333333333';
const aliasId = 'd4444444-4444-4444-8444-444444444444';
const relationshipId = 'e5555555-5555-4555-8555-555555555555';
const aliases = [{ alias_id: aliasId, org_id: organisationId }];
const relationships = [{ relationship_id: relationshipId, org_id: organisationId }];
let editor = true;

function deleteBuilder(rows) {
	const filters = new Map();
	return {
		eq(column, value) {
			filters.set(column, value);
			return this;
		},
		select() {
			return this;
		},
		async maybeSingle() {
			const index = rows.findIndex((row) =>
				[...filters].every(([column, value]) => row[column] === value)
			);
			if (index < 0) return { data: null, error: null };
			return { data: rows.splice(index, 1)[0], error: null };
		}
	};
}

const locals = {
	user: { id: userId },
	supabase: {
		async rpc(name, args) {
			assert.equal(name, 'user_max_role_level');
			assert.equal(args.p_organisation_id, organisationId);
			return { data: editor ? 3 : 0, error: null };
		},
		from(table) {
			const rows = table === 'aliases' ? aliases : table === 'relationships' ? relationships : null;
			assert.ok(rows, `Unexpected table ${table}`);
			return { delete: () => deleteBuilder(rows) };
		}
	}
};

function request(field, value) {
	return new Request('http://localhost/test', {
		method: 'POST',
		body: new URLSearchParams({ [field]: value })
	});
}

const vite = await createServer({
	server: { middlewareMode: true, hmr: false, ws: false },
	appType: 'custom'
});
try {
	const overview = await vite.ssrLoadModule('/src/routes/organisations/[id]/+page.server.ts');
	const relationshipPage = await vite.ssrLoadModule(
		'/src/routes/organisations/[id]/relationships/+page.server.ts'
	);

	let result = await overview.actions.deleteAlias({
		locals,
		params: { id: organisationId },
		request: request('alias_id', aliasId)
	});
	assert.equal(result.success, true);
	assert.equal(aliases.length, 0);

	aliases.push({ alias_id: aliasId, org_id: otherOrganisationId });
	result = await overview.actions.deleteAlias({
		locals,
		params: { id: organisationId },
		request: request('alias_id', aliasId)
	});
	assert.equal(result.status, 400);
	assert.equal(aliases.length, 1, 'another organisation alias must not be deleted');

	result = await relationshipPage.actions.deleteRelationship({
		locals,
		params: { id: organisationId },
		request: request('relationship_id', relationshipId)
	});
	assert.equal(result.success, true);
	assert.equal(relationships.length, 0);

	relationships.push({ relationship_id: relationshipId, org_id: otherOrganisationId });
	result = await relationshipPage.actions.deleteRelationship({
		locals,
		params: { id: organisationId },
		request: request('relationship_id', relationshipId)
	});
	assert.equal(result.status, 400);
	assert.equal(relationships.length, 1, 'another organisation relationship must not be deleted');

	editor = false;
	await assert.rejects(
		() =>
			overview.actions.deleteAlias({
				locals,
				params: { id: organisationId },
				request: request('alias_id', aliasId)
			}),
		(error) => error.status === 403
	);

	console.log('Directory correction deletion actions passed scoped-record and editor checks.');
} finally {
	await vite.close();
}
