import { error, fail } from '@sveltejs/kit';
import type { PageServerLoad, Actions } from './$types';
import { requireOrgAccess, requireOrgEditor } from '$lib/server/authorization';
import {
	actionFailure,
	actionSuccess,
	auditColumns,
	financialSchema,
	orgIdSchema,
	toColumns
} from '$lib/server/validation';

export const load: PageServerLoad = async ({ locals: { supabase, user }, params }) => {
	const orgId = orgIdSchema.safeParse(params.id);
	if (!orgId.success) {
		error(404, 'Organisation not found.');
	}

	/**
	 * The organisation is fetched separately rather than embedded in the
	 * financial_info row, so the page still renders its heading when an
	 * organisation has no financial details recorded yet.
	 */
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

	const { data: detail, error: detailError } = await supabase
		.from('financial_info')
		.select('*')
		.eq('org_id', orgId.data)
		.maybeSingle();

	if (detailError) {
		console.error('Failed to load financial details:', detailError);
		error(500, 'Could not load the financial details.');
	}

	return {
		organisation,
		roleLevel,
		financialInfo: detail
	};
};

export const actions: Actions = {
	updateFinancial: async ({ request, locals: { supabase, user }, params }) => {
		const orgId = orgIdSchema.safeParse(params.id);
		if (!orgId.success) {
			return fail(400, actionFailure('Not a valid organisation id.'));
		}
		await requireOrgEditor(supabase, user?.id, orgId.data);

		const form = Object.fromEntries(await request.formData());
		const parsed = financialSchema.safeParse(form);

		if (!parsed.success) {
			return fail(
				400,
				actionFailure('Please correct the highlighted fields.', parsed.error.flatten().fieldErrors)
			);
		}

		/**
		 * `onConflict` is required here. This table is keyed on `finance_id`, which
		 * the payload does not carry, so without it every save would insert a
		 * new row instead of updating the existing one — and the `maybeSingle`
		 * in the load above would then start erroring on duplicates.
		 */
		const { error: saveError } = await supabase.from('financial_info').upsert(
			{
				org_id: orgId.data,
				...toColumns(parsed.data),
				...auditColumns(user?.id)
			},
			{ onConflict: 'org_id' }
		);

		if (saveError) {
			console.error('Failed to save financial details:', saveError);
			return fail(400, actionFailure('Could not save your changes.'));
		}

		return actionSuccess();
	}
};
