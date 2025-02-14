import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ locals: { safeGetSession, supabase }, cookies }) => {
	const { session, user } = await safeGetSession();
	if (session) {
		const {
			data: { user }
		} = await supabase.auth.getUser();

		return {
			session,
			user,
			roles: '',
			cookies: cookies.getAll()
		};
	}
	return {
		session: {},
		user,
		roles: '',
		cookies: cookies.getAll()
	};
};
