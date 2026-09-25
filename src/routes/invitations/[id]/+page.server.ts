import { error, fail } from '@sveltejs/kit';
import { z } from 'zod';
import type { Actions, PageServerLoad } from './$types';

const invitationSchema = z.object({
	id: z.string().uuid(),
	organisationId: z.string().uuid(),
	organisationName: z.string(),
	email: z.string().email(),
	targetStewardship: z.enum(['self_managed', 'co_managed']),
	note: z.string(),
	expiresAt: z.string(),
	status: z.enum(['pending', 'accepted', 'cancelled', 'expired'])
});

export const load: PageServerLoad = async ({ locals, params, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	if (!z.string().uuid().safeParse(params.id).success) error(404, 'Invitation not found.');
	const result = await locals.providers.database.rpc('organisation_invitation', {
		p_invitation_id: params.id
	});
	if (result.error) {
		if (result.error.code === '42501')
			error(403, 'This invitation belongs to a different verified email address.');
		error(result.error.code === 'P0002' ? 404 : 500, 'Could not load this invitation.');
	}
	const parsed = invitationSchema.safeParse(result.data);
	if (!parsed.success) error(500, 'Could not load this invitation.');
	return { invitation: parsed.data };
};

export const actions: Actions = {
	accept: async ({ locals, params }) => {
		if (!z.string().uuid().safeParse(params.id).success)
			return fail(404, { success: false, message: 'Invitation not found.' });
		const result = await locals.providers.database.rpc('accept_organisation_invitation', {
			p_invitation_id: params.id
		});
		if (result.error)
			return fail(result.error.code === '42501' ? 403 : 409, {
				success: false,
				message:
					result.error.code === '42501'
						? 'Sign in with the verified email address named on this invitation.'
						: 'This invitation can no longer be accepted.'
			});
		const parsed = z
			.object({ status: z.enum(['accepted', 'cancelled', 'expired']) })
			.passthrough()
			.safeParse(result.data);
		if (!parsed.success)
			return fail(500, { success: false, message: 'Could not confirm the invitation result.' });
		if (parsed.data.status !== 'accepted')
			return fail(409, {
				success: false,
				message: `This invitation is ${parsed.data.status}. No access was granted.`
			});
		return { success: true, message: 'Invitation accepted. You are now an owner.' };
	}
};
