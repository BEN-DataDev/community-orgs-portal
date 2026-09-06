import { fail, redirect } from '@sveltejs/kit';
import { captchaOption } from '$lib/auth/captcha';
import { magicLinkSchema, signInSchema } from '$lib/auth/schemas';
import { safeRedirect } from '$lib/server/redirects';
import type { Actions } from './$types';

export const actions: Actions = {
	signin: async ({ request, url, locals: { supabase } }) => {
		const formData = await request.formData();
		const parsed = signInSchema.safeParse({
			email: formData.get('email'),
			password: formData.get('password')
		});

		if (!parsed.success) {
			const { email, password } = parsed.error.flatten().fieldErrors;
			return fail(400, {
				error: 'Please check the details below.',
				errors: { email: email?.[0], password: password?.[0] }
			});
		}

		const { error } = await supabase.auth.signInWithPassword({
			...parsed.data,
			options: { captchaToken: captchaOption(formData.get('captchaToken')) }
		});

		if (error) {
			console.error('Sign in failed:', error.message);
			/**
			 * Deliberately generic: distinguishing "no such account" from "wrong
			 * password" tells an attacker which addresses are registered.
			 */
			return fail(400, { error: 'That email and password combination was not recognised.' });
		}

		/**
		 * Outside any try/catch. SvelteKit signals a redirect by throwing, so
		 * wrapping this would turn a successful sign-in into a 500.
		 */
		redirect(303, safeRedirect(formData.get('redirectTo') ?? url.searchParams.get('redirectTo')));
	},

	/**
	 * Passwordless sign-in. Supabase mails a one-time link that lands on
	 * `/auth/confirm`, which verifies it as a `type=magiclink` OTP and forwards
	 * to `next`.
	 */
	magiclink: async ({ request, url, locals: { supabase } }) => {
		const formData = await request.formData();
		const parsed = magicLinkSchema.safeParse({ email: formData.get('email') });

		if (!parsed.success) {
			const { email } = parsed.error.flatten().fieldErrors;
			return fail(400, {
				error: 'Please check the details below.',
				errors: { email: email?.[0] }
			});
		}

		const next = safeRedirect(formData.get('redirectTo') ?? url.searchParams.get('redirectTo'));

		const { error } = await supabase.auth.signInWithOtp({
			email: parsed.data.email,
			options: {
				emailRedirectTo: `${url.origin}/auth/confirm?next=${encodeURIComponent(next)}`,
				/**
				 * A magic link doubles as sign-up: someone who has never registered
				 * gets an account on first use rather than a dead end. This is the
				 * whole friction argument for the flow, and it is safe because the
				 * account is worthless until the link in that mailbox is opened.
				 */
				shouldCreateUser: true,
				captchaToken: captchaOption(formData.get('captchaToken'))
			}
		});

		if (error) {
			// Logged, never surfaced — see the note in the password branch above.
			console.error('Magic link request failed:', error.message);
		}

		/**
		 * Unconditional, success or not. Branching here would tell a caller which
		 * addresses are registered, which is exactly what the generic message on
		 * the password branch exists to prevent.
		 */
		redirect(303, '/auth/check-email?reason=magiclink');
	}
};
