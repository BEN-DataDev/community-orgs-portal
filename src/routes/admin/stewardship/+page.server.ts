import { error, fail } from '@sveltejs/kit';
import { z } from 'zod';
import { isSiteAdmin } from '$lib/server/authorization';
import {
	stewardshipAdministrationSchema,
	stewardshipFilters,
	stewardshipState
} from '$lib/server/stewardship-administration';
import type { Actions, PageServerLoad } from './$types';

const allowedTransitions: Record<string, string[]> = {
	unclaimed: ['portal_managed', 'suspended'],
	invitation_pending: [],
	self_managed: ['co_managed', 'suspended'],
	portal_managed: ['unclaimed', 'suspended'],
	co_managed: ['self_managed', 'portal_managed', 'suspended'],
	suspended: ['unclaimed', 'portal_managed']
};

async function requireAdministrator(locals: App.Locals) {
	if (!(await isSiteAdmin(locals.supabase, locals.user?.id)))
		error(403, 'Portal Administrator required.');
}

export const load: PageServerLoad = async ({ locals, url, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	await requireAdministrator(locals);
	const filters = stewardshipFilters.safeParse({
		search: url.searchParams.get('search') || '',
		state: url.searchParams.get('state') || '',
		offset: url.searchParams.get('offset') || 0
	});
	if (!filters.success) error(400, 'Invalid stewardship filter.');
	const result = await locals.supabase.rpc('stewardship_administration_queue', {
		p_search: filters.data.search,
		p_state: filters.data.state,
		p_offset: filters.data.offset
	});
	const queue = stewardshipAdministrationSchema.safeParse(result.data);
	if (result.error || !queue.success)
		error(result.error?.code === '42501' ? 403 : 500, 'Could not load stewardship administration.');
	return { queue: queue.data, filters: filters.data };
};

export const actions: Actions = {
	default: async ({ locals, request }) => {
		await requireAdministrator(locals);
		const input = z
			.object({
				organisationId: z.string().uuid(),
				revision: z.coerce.number().int().positive(),
				nextState: stewardshipState.exclude(['invitation_pending']),
				reason: z.string().trim().min(1).max(2000),
				approvalReference: z.string().trim().max(500),
				note: z.string().trim().min(1).max(4000)
			})
			.safeParse(Object.fromEntries(await request.formData()));
		if (!input.success)
			return fail(400, { message: 'Choose a state and provide the required governance evidence.' });
		if (
			['self_managed', 'portal_managed', 'co_managed'].includes(input.data.nextState) &&
			!input.data.approvalReference
		)
			return fail(400, {
				message: 'An approval reference is required for this stewardship state.'
			});
		const currentResult = await locals.supabase.rpc('stewardship_administration_queue', {
			p_search: input.data.organisationId,
			p_offset: 0
		});
		const currentQueue = stewardshipAdministrationSchema.safeParse(currentResult.data);
		const current = currentQueue.success ? currentQueue.data.organisations[0] : undefined;
		if (
			currentResult.error ||
			!current ||
			current.revision !== input.data.revision ||
			!allowedTransitions[current.state]?.includes(input.data.nextState)
		)
			return fail(409, {
				message:
					current?.state === 'invitation_pending'
						? 'Close the pending invitation through invitation administration before changing stewardship.'
						: 'That stewardship transition is not available. Reload and review the current state.'
			});
		const result = await locals.supabase.rpc('set_organisation_stewardship', {
			p_organisation_id: input.data.organisationId,
			p_next_state: input.data.nextState,
			p_reason: input.data.reason,
			p_approval_reference: input.data.approvalReference || null,
			p_note: input.data.note,
			p_expected_revision: input.data.revision
		});
		if (result.error)
			return fail(result.error.code === '40001' ? 409 : result.error.code === '42501' ? 403 : 400, {
				message:
					result.error.code === '40001'
						? 'Stewardship changed. Reload before saving.'
						: 'Stewardship was not changed. Check the transition evidence.'
			});
		return { message: 'Stewardship decision recorded with a new immutable revision.' };
	}
};
