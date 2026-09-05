import type { EmailOtpType } from '@supabase/supabase-js';
import { redirect } from '@sveltejs/kit';

import type { RequestHandler } from './$types';

/**
 * A safe post-confirmation destination: a root-relative path, with no scheme,
 * no authority (`//host` is rejected) and no query or fragment of its own.
 *
 * Only `pathname` is ever replaced below, so the origin is preserved and this
 * was never an open redirect — but an unvalidated `next` still lets a crafted
 * confirmation link drop a just-confirmed user on any page in the application,
 * which is a useful primitive for phishing inside a trusted domain.
 */
const SAFE_NEXT = /^\/(?!\/)[a-z0-9\-/]*$/i;

function safeNext(value: string | null): string {
	return value && SAFE_NEXT.test(value) ? value : '/';
}

export const GET: RequestHandler = async ({ url, locals: { supabase } }) => {
	const token_hash = url.searchParams.get('token_hash');
	const type = url.searchParams.get('type') as EmailOtpType | null;
	const next = safeNext(url.searchParams.get('next'));

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
	}

	redirectTo.pathname = '/auth/error';
	redirect(303, redirectTo);
};
