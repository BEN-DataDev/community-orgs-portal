import { error, fail } from '@sveltejs/kit';
import type { PageServerLoad, Actions } from './$types';
import { requireOrgAccess, requireOrgEditor } from '$lib/server/authorization';
import {
	actionFailure,
	actionSuccess,
	auditColumns,
	creationColumns,
	locationSchema,
	operationsSchema,
	orgIdSchema,
	recordIdSchema,
	toColumns
} from '$lib/server/validation';

export const load: PageServerLoad = async ({ locals: { supabase, user }, params }) => {
	const orgId = orgIdSchema.safeParse(params.id);
	if (!orgId.success) {
		error(404, 'Organisation not found.');
	}

	const { data: organisation, error: organisationError } = await supabase
		.from('organisations')
		.select('org_id, entity_name, slug, is_public')
		.eq('org_id', orgId.data)
		.maybeSingle();

	if (organisationError) {
		console.error('Failed to load organisation:', organisationError);
		error(500, 'Could not load this organisation.');
	}

	if (!organisation) {
		error(404, 'Organisation not found.');
	}

	const roleLevel = await requireOrgAccess(supabase, user?.id, orgId.data, organisation.is_public);

	const [operations, locations] = await Promise.all([
		supabase.from('operational_details').select('*').eq('org_id', orgId.data).maybeSingle(),
		/**
		 * `geom` is a generated PostGIS column and is not selected — the map
		 * reads the plain `latitude` / `longitude` the application writes.
		 */
		supabase
			.from('locations')
			.select('location_id, name, address, location_type, latitude, longitude')
			.eq('org_id', orgId.data)
			.order('name', { ascending: true })
	]);

	if (operations.error) {
		console.error('Failed to load operational details:', operations.error);
		error(500, 'Could not load the operational details.');
	}

	if (locations.error) {
		console.error('Failed to load locations:', locations.error);
		error(500, 'Could not load the locations.');
	}

	return {
		organisation,
		roleLevel,
		operationalInfo: operations.data,
		locations: locations.data ?? []
	};
};

export const actions: Actions = {
	updateOperations: async ({ request, locals: { supabase, user }, params }) => {
		const orgId = orgIdSchema.safeParse(params.id);
		if (!orgId.success) {
			return fail(400, actionFailure('Not a valid organisation id.'));
		}
		await requireOrgEditor(supabase, user?.id, orgId.data);

		const form = Object.fromEntries(await request.formData());
		const parsed = operationsSchema.safeParse(form);

		if (!parsed.success) {
			return fail(
				400,
				actionFailure('Please correct the highlighted fields.', parsed.error.flatten().fieldErrors)
			);
		}

		/**
		 * `onConflict` is required here. This table is keyed on `op_id`, which
		 * the payload does not carry, so without it every save would insert a
		 * new row instead of updating the existing one.
		 */
		const { error: saveError } = await supabase.from('operational_details').upsert(
			{
				org_id: orgId.data,
				...toColumns(parsed.data),
				...auditColumns(user?.id)
			},
			{ onConflict: 'org_id' }
		);

		if (saveError) {
			console.error('Failed to save operational details:', saveError);
			return fail(400, actionFailure('Could not save your changes.'));
		}

		return actionSuccess();
	},

	addLocation: async ({ request, locals: { supabase, user }, params }) => {
		const orgId = orgIdSchema.safeParse(params.id);
		if (!orgId.success) {
			return fail(400, actionFailure('Not a valid organisation id.'));
		}
		await requireOrgEditor(supabase, user?.id, orgId.data);

		const form = Object.fromEntries(await request.formData());
		const parsed = locationSchema.safeParse(form);

		if (!parsed.success) {
			return fail(
				400,
				actionFailure('Please correct the highlighted fields.', parsed.error.flatten().fieldErrors)
			);
		}

		/**
		 * Only `latitude` / `longitude` are written. The `geom` Point column is
		 * generated from them by the database.
		 */
		const { error: insertError } = await supabase.from('locations').insert({
			org_id: orgId.data,
			name: parsed.data.name,
			address: parsed.data.address ?? null,
			location_type: parsed.data.location_type ?? null,
			latitude: parsed.data.latitude ?? null,
			longitude: parsed.data.longitude ?? null,
			...creationColumns(user?.id)
		});

		if (insertError) {
			console.error('Failed to add location:', insertError);
			return fail(400, actionFailure('Could not add that location.'));
		}

		return actionSuccess();
	},

	deleteLocation: async ({ request, locals: { supabase, user }, params }) => {
		const orgId = orgIdSchema.safeParse(params.id);
		if (!orgId.success) {
			return fail(400, actionFailure('Not a valid organisation id.'));
		}
		await requireOrgEditor(supabase, user?.id, orgId.data);

		const locationId = recordIdSchema.safeParse((await request.formData()).get('location_id'));
		if (!locationId.success) {
			return fail(400, actionFailure('Not a valid location id.'));
		}

		// Scoped by org_id as well, so an id from another organisation cannot be used.
		const { error: deleteError } = await supabase
			.from('locations')
			.delete()
			.eq('location_id', locationId.data)
			.eq('org_id', orgId.data);

		if (deleteError) {
			console.error('Failed to delete location:', deleteError);
			return fail(400, actionFailure('Could not remove that location.'));
		}

		return actionSuccess();
	}
};
