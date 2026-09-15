import { fail, redirect } from '@sveltejs/kit';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals: { session } }) => {
	if (!session) {
		redirect(303, '/auth/signin');
	}
	return {};
};

export const actions: Actions = {
	/**
	 * Signing out is a state change, so it is a POST rather than a link — a GET
	 * endpoint here could be triggered by any third-party page embedding it.
	 */
	default: async ({ locals: { supabase } }) => {
		const { error } = await supabase.auth.signOut({ scope: 'local' });
		if (error) {
			return fail(400, { error: 'Could not sign out. Please try again.' });
		}
		redirect(303, '/');
	}
};
