import { fail, redirect } from '@sveltejs/kit';
import { z } from 'zod';
import { safeRedirect } from '$lib/server/redirects';
import type { Actions } from './$types';

const signInSchema = z.object({
	email: z.string().trim().email('Enter a valid email address'),
	password: z.string().min(1, 'Enter your password')
});

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

		const { error } = await supabase.auth.signInWithPassword(parsed.data);

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
	}
};
