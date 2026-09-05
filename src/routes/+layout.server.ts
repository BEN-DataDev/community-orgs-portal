import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ locals, cookies }) => {
	/**
	 * `authGuard` in `hooks.server.ts` has already run `safeGetSession()` for
	 * this request and put the result on `locals`, so reuse it. Calling
	 * `safeGetSession()` again here would repeat its `getUser()` round-trip to
	 * Supabase Auth on every single navigation.
	 *
	 * When there is no session both values are `null` — returning an empty
	 * object instead would be truthy in every downstream `if (session)` check.
	 */
	return {
		session: locals.session,
		user: locals.user,
		roles: '',
		cookies: cookies.getAll()
	};
};
