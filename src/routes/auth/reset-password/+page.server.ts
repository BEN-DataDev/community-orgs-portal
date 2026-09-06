import { fail, redirect } from '@sveltejs/kit';
import { newPasswordSchema } from '$lib/auth/schemas';
import type { Actions, PageServerLoad } from './$types';

/**
 * Reached only after `/auth/confirm` has verified a `type=recovery` token and
 * put a session on the request. Landing here without one means the link expired,
 * was already used, or the page was opened directly.
 */
export const load: PageServerLoad = async ({ locals }) => {
	if (!locals.session) {
		redirect(303, '/auth/forgot-password');
	}
	return {};
};

export const actions: Actions = {
	update: async ({ request, locals: { supabase, session } }) => {
		if (!session) {
			redirect(303, '/auth/forgot-password');
		}

		const formData = await request.formData();
		const password = formData.get('password');
		const confirmation = formData.get('passwordConfirmation');

		const parsed = newPasswordSchema.safeParse({ password });

		if (!parsed.success) {
			const fieldErrors = parsed.error.flatten().fieldErrors;
			return fail(400, {
				error: 'Please check the details below.',
				errors: { password: fieldErrors.password?.[0] }
			});
		}

		/**
		 * Checked on the server as well as in the component: the confirmation
		 * field is the only guard against a typo becoming a password nobody
		 * knows, and a client-side check alone is not one.
		 */
		if (parsed.data.password !== confirmation) {
			return fail(400, {
				error: 'Please check the details below.',
				errors: { password: 'Passwords do not match' }
			});
		}

		const { error } = await supabase.auth.updateUser({ password: parsed.data.password });

		if (error) {
			console.error('Password update failed:', error.message);
			return fail(400, {
				error: 'Could not set that password. It may have been used before, or the link has expired.'
			});
		}

		// Outside any try/catch — see the note in the sign-in action.
		redirect(303, '/organisations');
	}
};
