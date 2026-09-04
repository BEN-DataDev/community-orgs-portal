import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ locals: { safeGetSession }, cookies }) => {
	/**
	 * `safeGetSession` has already validated the JWT with `getUser()`, so both
	 * values here are trustworthy. When there is no session both are `null` —
	 * returning an empty object instead would be truthy in every downstream
	 * `if (session)` check.
	 */
	const { session, user } = await safeGetSession();

	return {
		session,
		user,
		roles: '',
		cookies: cookies.getAll()
	};
};
