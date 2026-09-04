import { error, fail } from '@sveltejs/kit';
import type { PageServerLoad, Actions } from './$types';
import { requireOrgAccess, requireOrgEditor } from '$lib/server/authorization';
import {
	actionFailure,
	actionSuccess,
	creationColumns,
	historySchema,
	orgIdSchema,
	toColumns
} from '$lib/server/validation';

export const load: PageServerLoad = async ({ locals: { supabase, user }, params }) => {
	const orgId = orgIdSchema.safeParse(params.id);
	if (!orgId.success) {
		error(404, 'Organisation not found.');
	}

	/**
	 * `inserted_by` and `last_edited_by` are scalar audit columns, not foreign
	 * keys to an exposed table, so they cannot be embedded as `inserted_by(name,
	 * email)` — that request is what made the whole row type unresolvable.
	 */
	const [historicalInfo, organisation] = await Promise.all([
		supabase
			.from('historical_info')
			.select('*')
			.eq('org_id', orgId.data)
			.order('milestone_date', { ascending: false }),
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

	if (historicalInfo.error) {
		console.error('Failed to load history:', historicalInfo.error);
		error(500, 'Could not load the history.');
	}

	const roleLevel = await requireOrgAccess(
		supabase,
		user?.id,
		orgId.data,
		organisation.data.is_public
	);

	return {
		historicalInfo: historicalInfo.data ?? [],
		organisation: organisation.data,
		roleLevel
	};
};

export const actions: Actions = {
	addHistoryEntry: async ({ request, locals: { supabase, user }, params }) => {
		const orgId = orgIdSchema.safeParse(params.id);
		if (!orgId.success) {
			return fail(400, actionFailure('Not a valid organisation id.'));
		}
		await requireOrgEditor(supabase, user?.id, orgId.data);

		const form = Object.fromEntries(await request.formData());
		const parsed = historySchema.safeParse(form);

		if (!parsed.success) {
			return fail(
				400,
				actionFailure('Please correct the highlighted fields.', parsed.error.flatten().fieldErrors)
			);
		}

		/**
		 * History is a milestone log: each submission is a new entry, so this
		 * inserts rather than upserting on `org_id` the way the one-to-one
		 * tables do.
		 */
		const { error: insertError } = await supabase.from('historical_info').insert({
			org_id: orgId.data,
			...toColumns(parsed.data),
			...creationColumns(user?.id)
		});

		if (insertError) {
			console.error('Failed to add history entry:', insertError);
			return fail(400, actionFailure('Could not save this entry.'));
		}

		return actionSuccess();
	}
};
