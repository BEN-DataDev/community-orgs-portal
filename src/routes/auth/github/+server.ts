import { redirect } from '@sveltejs/kit';

import { safeRedirect } from '$lib/server/redirects';
import type { RequestHandler } from './$types';

/**
 * Starts the GitHub OAuth flow.
 *
 * POST rather than GET, and a full form submission rather than an enhanced
 * one: the response is a redirect to github.com, and `use:enhance` hands
 * redirects to `goto()`, which only navigates within the app. Letting the
 * browser follow this itself is what makes it work.
 *
 * `signInWithOAuth` on a server client does not sign anyone in. It builds the
 * authorize URL and stores the PKCE verifier in a cookie, which
 * `/auth/callback` needs to complete the exchange.
 */
export const POST: RequestHandler = async ({ request, url, locals: { supabase } }) => {
	const formData = await request.formData();

	/**
	 * Where to land once GitHub comes back. Passed through the provider as a
	 * query parameter on our own callback URL, so it has to survive a round
	 * trip through a third party — hence the check on the way back out in
	 * `/auth/callback` as well as here.
	 */
	const next = safeRedirect(formData.get('redirectTo') ?? url.searchParams.get('redirectTo'));

	const { data, error } = await supabase.auth.signInWithOAuth({
		provider: 'github',
		options: {
			redirectTo: `${url.origin}/auth/callback?next=${encodeURIComponent(next)}`
		}
	});

	if (error || !data.url) {
		/**
		 * Nearly always a configuration fault rather than anything the visitor
		 * did: the provider disabled in the Supabase project, or credentials
		 * that are missing or wrong.
		 */
		console.error('Could not start GitHub sign-in:', error?.message);
		redirect(303, '/auth/error');
	}

	redirect(303, data.url);
};
