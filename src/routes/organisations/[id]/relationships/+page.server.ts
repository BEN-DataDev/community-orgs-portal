import { error, fail } from '@sveltejs/kit';
import type { PageServerLoad, Actions } from './$types';
import { requireOrgAccess, requireOrgEditor } from '$lib/server/authorization';
import {
	actionFailure,
	actionSuccess,
	creationColumns,
	orgIdSchema,
	relationshipSchema,
	toColumns
} from '$lib/server/validation';

export const load: PageServerLoad = async ({ locals: { supabase, user }, params }) => {
	const orgId = orgIdSchema.safeParse(params.id);
	if (!orgId.success) {
		error(404, 'Organisation not found.');
	}

	/**
	 * `partner_org` is a plain text column, not a foreign key, so there is no
	 * `organisations` relation to embed here — attempting one is what produced
	 * "could not find the relation between relationships and organisations".
	 */
	const [relationships, organisation] = await Promise.all([
		supabase
			.from('relationships')
			.select('*')
			.eq('org_id', orgId.data)
			.order('start_date', { ascending: false }),
		supabase
			.from('organisations')
			.select('org_id, entity_name, slug, is_public')
			.eq('org_id', orgId.data)
			.maybeSingle()
	]);

	if (organisation.error) {
		console.error('Failed to load organisation:', organisation.error);
		error(500, 'Could not load this organisation.');
	}

	if (!organisation.data) {
		error(404, 'Organisation not found.');
	}

	if (relationships.error) {
		console.error('Failed to load relationships:', relationships.error);
		error(500, 'Could not load the relationships.');
	}

	const roleLevel = await requireOrgAccess(
		supabase,
		user?.id,
		orgId.data,
		organisation.data.is_public
	);

	return {
		relationships: relationships.data ?? [],
		organisation: organisation.data,
		roleLevel
	};
};

export const actions: Actions = {
	createRelationship: async ({ request, locals: { supabase, user }, params }) => {
		const orgId = orgIdSchema.safeParse(params.id);
		if (!orgId.success) {
			return fail(400, actionFailure('Not a valid organisation id.'));
		}
		await requireOrgEditor(supabase, user?.id, orgId.data);

		const form = Object.fromEntries(await request.formData());
		const parsed = relationshipSchema.safeParse(form);

		if (!parsed.success) {
			return fail(
				400,
				actionFailure('Please correct the highlighted fields.', parsed.error.flatten().fieldErrors)
			);
		}

		const { error: insertError } = await supabase.from('relationships').insert({
			org_id: orgId.data,
			...toColumns(parsed.data),
			...creationColumns(user?.id)
		});

		if (insertError) {
			console.error('Failed to create relationship:', insertError);
			return fail(400, actionFailure('Could not add the relationship.'));
		}

		return actionSuccess();
	}
};
