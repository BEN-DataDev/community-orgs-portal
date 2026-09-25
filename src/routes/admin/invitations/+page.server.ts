import { error, fail } from '@sveltejs/kit';
import { z } from 'zod';
import { isSiteAdmin } from '$lib/server/authorization';
import {
	invitationFilters,
	stewardshipAdministrationSchema
} from '$lib/server/stewardship-administration';
import type { Actions, PageServerLoad } from './$types';

async function requireAdministrator(locals: App.Locals) {
	if (!(await isSiteAdmin(locals.providers.database, locals.user?.id)))
		error(403, 'Portal Administrator required.');
}

export const load: PageServerLoad = async ({ locals, url, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	await requireAdministrator(locals);
	const filters = invitationFilters.safeParse({
		search: url.searchParams.get('search') || '',
		status: url.searchParams.get('status') || '',
		offset: url.searchParams.get('offset') || 0
	});
	if (!filters.success) error(400, 'Invalid invitation filter.');
	const result = await locals.providers.database.rpc('stewardship_administration_queue', {
		p_search: filters.data.search,
		p_invitation_status: filters.data.status,
		p_offset: filters.data.offset
	});
	const queue = stewardshipAdministrationSchema.safeParse(result.data);
	if (result.error || !queue.success)
		error(result.error?.code === '42501' ? 403 : 500, 'Could not load invitation administration.');
	return { queue: queue.data, filters: filters.data };
};

export const actions: Actions = {
	cancel: async ({ locals, request }) => {
		await requireAdministrator(locals);
		const input = z
			.object({ invitationId: z.string().uuid(), reason: z.string().trim().min(1).max(2000) })
			.safeParse(Object.fromEntries(await request.formData()));
		if (!input.success)
			return fail(400, { message: 'A valid invitation and cancellation reason are required.' });
		const result = await locals.providers.database.rpc('cancel_organisation_invitation', {
			p_invitation_id: input.data.invitationId,
			p_reason: input.data.reason
		});
		if (result.error)
			return fail(result.error.code === '42501' ? 403 : 400, {
				message: 'The invitation could not be cancelled.'
			});
		if (!result.data) return fail(409, { message: 'That invitation is already closed.' });
		return { message: 'Invitation closed without granting access.' };
	}
};
