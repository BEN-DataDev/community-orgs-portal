import { redirect } from '@sveltejs/kit';

import { safeRedirect } from '$lib/server/redirects';
import type { RequestHandler } from './$types';

/**
 * Where OAuth providers return to. Exchanges the one-time code for a session
 * and sets the auth cookies.
 *
 * Distinct from `/auth/confirm`, which handles the email link flow and its
 * `token_hash` / `type` pair. This one handles the PKCE `code` that
 * `/auth/github` set up.
 */
export const GET: RequestHandler = async ({ url, locals: { supabase } }) => {
	const code = url.searchParams.get('code');

	/**
	 * `next` has been outside our control since it was handed to GitHub, so it
	 * is re-checked here rather than trusted. `safeRedirect` falls back to
	 * /organisations for anything that is not a plain in-app path.
	 */
	const next = safeRedirect(url.searchParams.get('next'));

	/**
	 * The provider reports a refusal — most often the visitor declining the
	 * authorisation prompt — as an error parameter rather than a code.
	 */
	const providerError = url.searchParams.get('error_description') ?? url.searchParams.get('error');
	if (providerError) {
		console.error('GitHub returned an error:', providerError);
		redirect(303, '/auth/error');
	}

	if (!code) {
		redirect(303, '/auth/error');
	}

	const { error } = await supabase.auth.exchangeCodeForSession(code);

	if (error) {
		/**
		 * A code that is expired, already spent, or paired with a PKCE verifier
		 * cookie that is missing — a stale callback URL being reloaded, for
		 * instance.
		 */
		console.error('Could not complete GitHub sign-in:', error.message);
		redirect(303, '/auth/error');
	}

	redirect(303, next);
};
