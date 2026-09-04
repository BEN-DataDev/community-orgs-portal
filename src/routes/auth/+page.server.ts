import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';

/**
 * `/auth` used to host a second, unvalidated copy of the sign-in and sign-up
 * forms. Two credential paths mean two places to keep correct, so this now
 * redirects to the canonical one.
 */
export const load: PageServerLoad = async () => {
	redirect(308, '/auth/signin');
};
