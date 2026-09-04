import { error, fail } from '@sveltejs/kit';
import type { PageServerLoad, Actions } from './$types';
import { requireOrgAccess, requireOrgEditor } from '$lib/server/authorization';
import {
	actionFailure,
	actionSuccess,
	aliasSchema,
	auditColumns,
	organisationSchema,
	orgIdSchema,
	toColumns
} from '$lib/server/validation';

export const load: PageServerLoad = async ({ locals: { supabase, user }, params }) => {
	const orgId = orgIdSchema.safeParse(params.id);
	if (!orgId.success) {
		error(404, 'Organisation not found.');
	}

	const { data: organisation, error: loadError } = await supabase
		.from('organisations')
		.select(
			`
            *,
            aliases (*),
            legal_details (*),
            contact_info (*),
            operational_details (*),
            financial_info (*),
            governance (*),
            programs_services (*),
            accreditation (*),
            resources_assets (*)
        `
		)
		.eq('org_id', orgId.data)
		.maybeSingle();

	if (loadError) {
		console.error('Failed to load organisation:', loadError);
		error(500, 'Could not load this organisation.');
	}

	if (!organisation) {
		error(404, 'Organisation not found.');
	}

	const roleLevel = await requireOrgAccess(supabase, user?.id, orgId.data, organisation.is_public);

	const { data: relationships, error: relationshipsError } = await supabase
		.from('relationships')
		.select('*')
		.eq('org_id', orgId.data);

	if (relationshipsError) {
		console.error('Failed to load relationships:', relationshipsError);
		error(500, 'Could not load this organisation.');
	}

	return {
		organisation,
		relationships: relationships ?? [],
		roleLevel
	};
};

export const actions: Actions = {
	updateOrganisation: async ({ request, locals: { supabase, user }, params }) => {
		const orgId = orgIdSchema.safeParse(params.id);
		if (!orgId.success) {
			return fail(400, actionFailure('Not a valid organisation id.'));
		}
		await requireOrgEditor(supabase, user?.id, orgId.data);

		const form = Object.fromEntries(await request.formData());
		const parsed = organisationSchema.safeParse(form);

		if (!parsed.success) {
			return fail(
				400,
				actionFailure('Please correct the highlighted fields.', parsed.error.flatten().fieldErrors)
			);
		}

		const { error: updateError } = await supabase
			.from('organisations')
			.update({ ...toColumns(parsed.data), ...auditColumns(user?.id) })
			.eq('org_id', orgId.data);

		if (updateError) {
			console.error('Failed to update organisation:', updateError);
			return fail(400, actionFailure('Could not save your changes.'));
		}

		return actionSuccess();
	},

	/** Trading and business names live in `aliases`, not on `organisations`. */
	addAlias: async ({ request, locals: { supabase, user }, params }) => {
		const orgId = orgIdSchema.safeParse(params.id);
		if (!orgId.success) {
			return fail(400, actionFailure('Not a valid organisation id.'));
		}
		await requireOrgEditor(supabase, user?.id, orgId.data);

		const form = Object.fromEntries(await request.formData());
		const parsed = aliasSchema.safeParse(form);

		if (!parsed.success) {
			return fail(
				400,
				actionFailure('Please correct the highlighted fields.', parsed.error.flatten().fieldErrors)
			);
		}

		const { error: insertError } = await supabase.from('aliases').insert({
			org_id: orgId.data,
			alias: parsed.data.alias,
			alias_type: parsed.data.alias_type,
			inserted_by: user?.id ?? null,
			...auditColumns(user?.id)
		});

		if (insertError) {
			console.error('Failed to add alias:', insertError);
			return fail(400, actionFailure('Could not add that name.'));
		}

		return actionSuccess();
	}
};
