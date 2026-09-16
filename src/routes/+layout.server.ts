import type { LayoutServerLoad } from './$types';
import { loadAccountAvatar } from '$lib/server/account-avatar';
import { isIngestionOperator } from '$lib/server/ingestion-review';
import { EDITOR_LEVEL } from '$lib/role-levels';

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
	// Fetch memberships once for both navigation and the account menu. A failed
	// lookup must remain distinguishable from an account with no memberships.
	const membershipResult =
		locals.user && !locals.isAnonymous
			? await locals.supabase.rpc('get_user_organisations_with_roles', {
					p_user_id: locals.user.id
				})
			: { data: [], error: null };
	if (membershipResult.error)
		console.error('Could not load account access:', membershipResult.error.message);
	const memberships = membershipResult.error
		? null
		: (membershipResult.data ?? []).map((org) => ({
				organisation_id: org.organisation_id,
				organisation_name: org.organisation_name,
				max_hierarchy_level: org.max_hierarchy_level,
				role_names: org.role_names
			}));
	const avatar =
		locals.user && !locals.isAnonymous
			? await loadAccountAvatar(locals.supabase, locals.user)
			: null;
	return {
		isIngestionOperator:
			locals.user && !locals.isAnonymous ? await isIngestionOperator(locals.supabase) : false,
		avatar,
		session: locals.session,
		user: locals.user,
		aal: locals.aal,
		isAnonymous: locals.isAnonymous,
		memberships,
		isSiteAdmin: memberships?.some((org) => org.max_hierarchy_level >= EDITOR_LEVEL) ?? false,
		cookies: cookies.getAll()
	};
};
