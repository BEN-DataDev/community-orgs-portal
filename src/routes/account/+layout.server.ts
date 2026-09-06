import { error, redirect } from '@sveltejs/kit';
import type { LayoutServerLoad } from './$types';

/**
 * Account settings. The session itself is guaranteed by `authGuard` in
 * `hooks.server.ts`; what is added here is that a guest cannot get in.
 *
 * An anonymous user has no password to change and no email to send a factor
 * recovery to, so every control on these pages would be inert for them. They are
 * pointed at sign-up instead, which is the thing that would make this area
 * useful to them.
 */
export const load: LayoutServerLoad = async ({ locals }) => {
	if (!locals.session) {
		redirect(303, '/auth/signin?redirectTo=/account/security');
	}

	if (locals.isAnonymous) {
		error(403, 'Create an account to manage account settings.');
	}

	return { user: locals.user };
};
