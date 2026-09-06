import { redirect } from '@sveltejs/kit';

import { safeRedirect } from '$lib/server/redirects';
import type { RequestHandler } from './$types';

/**
 * Starts a guest session.
 *
 * The visitor gets a real JWT and the same `authenticated` Postgres role as
 * anyone else — the only thing marking them out is the `is_anonymous` claim.
 * Restrictive RLS policies use that claim to confine them to reading public
 * organisations; see `restrict_anonymous_to_public_reads`. Nothing about this
 * endpoint grants access on its own.
 *
 * POST only. A GET would let any link, prefetch or crawler mint accounts.
 */
export const POST: RequestHandler = async ({ request, locals: { supabase } }) => {
	const formData = await request.formData();

	/**
	 * Supabase Auth verifies this against Turnstile itself, using the secret set
	 * under `[auth.captcha]`. Every anonymous sign-in writes a row to auth.users,
	 * which makes an unprotected endpoint a free way to grow someone else's
	 * database, so a missing token is refused here rather than passed on.
	 */
	const captchaToken = formData.get('captchaToken');
	if (typeof captchaToken !== 'string' || captchaToken === '') {
		redirect(303, '/auth/signin');
	}

	const next = safeRedirect(formData.get('redirectTo'));

	const { error } = await supabase.auth.signInAnonymously({ options: { captchaToken } });

	if (error) {
		console.error('Anonymous sign-in failed:', error.message);
		redirect(303, '/auth/error?reason=exchange');
	}

	redirect(303, next);
};
