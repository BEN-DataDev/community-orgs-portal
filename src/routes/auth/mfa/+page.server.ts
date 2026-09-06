import { redirect } from '@sveltejs/kit';
import { safeRedirect } from '$lib/server/redirects';
import type { PageServerLoad } from './$types';

/**
 * The second-factor challenge screen.
 *
 * Only reachable with a session that has a factor enrolled but has not yet
 * satisfied it. Anyone else is sent on: someone with no factor has nothing to
 * type, and someone already at aal2 has nothing left to prove.
 */
export const load: PageServerLoad = async ({ locals, url }) => {
	if (!locals.session) {
		redirect(303, '/auth/signin');
	}

	const redirectTo = safeRedirect(url.searchParams.get('redirectTo'));

	if (locals.aal?.nextLevel !== 'aal2' || locals.aal.currentLevel === 'aal2') {
		redirect(303, redirectTo);
	}

	return { redirectTo };
};
