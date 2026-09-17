import type { PageServerLoad } from './$types';
import { requireAdminAccess } from '$lib/server/admin-access';

export const load: PageServerLoad = async ({ locals, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	await requireAdminAccess(
		locals.supabase,
		locals.isAnonymous ? undefined : locals.user?.id,
		'/admin'
	);
	return { adminData: {} };
};
