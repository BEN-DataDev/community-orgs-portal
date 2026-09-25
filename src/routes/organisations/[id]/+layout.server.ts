import type { LayoutServerLoad } from './$types';
import { z } from 'zod';

export const load: LayoutServerLoad = async ({ locals, params }) => {
	if (!locals.user || locals.isAnonymous || !z.string().uuid().safeParse(params.id).success)
		return { canManageAccess: false };
	const { data, error } = await locals.providers.database.rpc('user_has_permission', {
		p_user_id: locals.user.id,
		p_organisation_id: params.id,
		p_permission: 'can_manage_members'
	});
	return { canManageAccess: !error && data === true };
};
