import { fail, redirect } from '@sveltejs/kit';
import type { Actions } from './$types';
import { z } from 'zod';

const registerSchema = z.object({
	email: z.string().email(),
	password: z.string().min(6)
});

export const actions: Actions = {
	default: async ({ request, locals }) => {
		const formData = await request.formData();
		const email = formData.get('email');
		const password = formData.get('password');

		const result = registerSchema.safeParse({ email, password });

		if (!result.success) {
			return fail(400, {
				error: 'Invalid input',
				errors: result.error.flatten().fieldErrors
			});
		}

		try {
			// Add your authentication logic here
			// Example: await locals.auth.createUser({ email, password });

			throw redirect(303, '/auth/login');
		} catch (error) {
			return fail(500, {
				error: 'Failed to create account'
			});
		}
	}
};
