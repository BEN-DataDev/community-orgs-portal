import { fail, redirect } from '@sveltejs/kit';
import { z } from 'zod';
import type { Actions } from './$types';

const signUpSchema = z.object({
	email: z.string().trim().email('Enter a valid email address'),
	password: z.string().min(8, 'Use at least 8 characters')
});

export const actions: Actions = {
	signup: async ({ request, url, locals: { supabase } }) => {
		const formData = await request.formData();
		const parsed = signUpSchema.safeParse({
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

		const { error } = await supabase.auth.signUp({
			email: parsed.data.email,
			password: parsed.data.password,
			options: { emailRedirectTo: `${url.origin}/auth/confirm` }
		});

		if (error) {
			console.error('Sign up failed:', error.message);
			return fail(400, { error: 'Could not create that account. Try a different email address.' });
		}

		// Outside any try/catch — see the note in the sign-in action.
		redirect(303, '/auth/check-email');
	}
};
