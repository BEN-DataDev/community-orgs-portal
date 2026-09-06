import type { EmailOtpType } from '@supabase/supabase-js';
import { redirect } from '@sveltejs/kit';

import { safeRedirect } from '$lib/server/redirects';
import type { RequestHandler } from './$types';

/**
 * `next` decides where a just-confirmed user lands. Only `pathname` is ever
 * replaced below, so the origin is preserved and this was never an open
 * redirect — but an unvalidated `next` still lets a crafted confirmation link
 * drop the user on any page in the application, which is a useful primitive for
 * phishing inside a trusted domain.
 *
 * This used to be a second, subtly different regex living in this file.
 * `safeRedirect` is the same check the sign-in action and the OAuth hand-off
 * already use.
 */
export const GET: RequestHandler = async ({ url, locals: { supabase } }) => {
	const token_hash = url.searchParams.get('token_hash');
	const type = url.searchParams.get('type') as EmailOtpType | null;
	const next = safeRedirect(url.searchParams.get('next'), '/');

	/**
	 * Clean up the redirect URL by deleting the Auth flow parameters.
	 *
	 * `next` is preserved for now, because it's needed in the error case.
	 */
	const redirectTo = new URL(url);
	redirectTo.pathname = next;
	redirectTo.searchParams.delete('token_hash');
	redirectTo.searchParams.delete('type');

	if (token_hash && type) {
		const { error } = await supabase.auth.verifyOtp({ type, token_hash });
		if (!error) {
			redirectTo.searchParams.delete('next');
			redirect(303, redirectTo);
		}
		console.error(`Could not verify ${type} link:`, error.message);
	}

	/**
	 * By far the most common cause is a link that has expired or been opened
	 * twice, so `/auth/error` says so rather than offering a generic failure.
	 */
	redirectTo.pathname = '/auth/error';
	redirectTo.searchParams.delete('next');
	redirectTo.searchParams.set('reason', 'expired');
	redirect(303, redirectTo);
};
