import { fail, redirect } from '@sveltejs/kit';
import { captchaOption } from '$lib/auth/captcha';
import { resetRequestSchema } from '$lib/auth/schemas';
import type { Actions } from './$types';

export const actions: Actions = {
	request: async ({ request, url, locals: { supabase } }) => {
		const formData = await request.formData();
		const parsed = resetRequestSchema.safeParse({ email: formData.get('email') });

		if (!parsed.success) {
			const { email } = parsed.error.flatten().fieldErrors;
			return fail(400, {
				error: 'Please check the details below.',
				errors: { email: email?.[0] }
			});
		}

		/**
		 * The recovery email lands on `/auth/confirm`, which verifies the
		 * `type=recovery` token and establishes a session, then forwards to
		 * `/auth/reset-password` where the new password is actually set.
		 */
		const { error } = await supabase.auth.resetPasswordForEmail(parsed.data.email, {
			redirectTo: `${url.origin}/auth/confirm?next=/auth/reset-password`,
			captchaToken: captchaOption(formData.get('captchaToken'))
		});

		if (error) {
			/**
			 * Logged, but not surfaced. Telling the caller that no account exists
			 * for an address turns this form into an account-enumeration oracle —
			 * the same reason the sign-in action returns one generic message.
			 * Rate-limit rejections are swallowed here too; the alternative leaks
			 * that the address is real enough to have been mailed recently.
			 */
			console.error('Password reset request failed:', error.message);
		}

		// Outside any try/catch — see the note in the sign-in action.
		redirect(303, '/auth/check-email?reason=recovery');
	}
};
