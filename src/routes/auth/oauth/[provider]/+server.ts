import { error, redirect } from '@sveltejs/kit';

import { isOAuthProvider, oauthProviderLabel, PROVIDER_SCOPES } from '$lib/auth/providers';
import { safeRedirect } from '$lib/server/redirects';
import type { RequestHandler } from './$types';

/**
 * Starts an OAuth flow with one of the providers in `$lib/auth/providers`.
 *
 * POST rather than GET, and a full form submission rather than an enhanced
 * one: the response is a redirect off-site, and `use:enhance` hands redirects
 * to `goto()`, which only navigates within the app. Letting the browser follow
 * this itself is what makes it work.
 *
 * `signInWithOAuth` on a server client does not sign anyone in. It builds the
 * authorize URL and stores the PKCE verifier in a cookie, which
 * `/auth/callback` needs to complete the exchange.
 */
export const POST: RequestHandler = async ({ request, params, url, locals: { supabase } }) => {
	/**
	 * The provider comes from the URL, so it is checked against the allow-list
	 * before it reaches `signInWithOAuth`. A 400 rather than a redirect to
	 * `/auth/error`: this is a malformed request, not a failed sign-in.
	 */
	if (!isOAuthProvider(params.provider)) {
		error(400, 'Unknown sign-in provider.');
	}
	const provider = params.provider;

	const formData = await request.formData();

	/**
	 * Where to land once the provider comes back. Passed through as a query
	 * parameter on our own callback URL, so it has to survive a round trip
	 * through a third party — hence the check on the way back out in
	 * `/auth/callback` as well as here.
	 */
	const next = safeRedirect(formData.get('redirectTo') ?? url.searchParams.get('redirectTo'));

	const { data, error: oauthError } = await supabase.auth.signInWithOAuth({
		provider,
		options: {
			redirectTo: `${url.origin}/auth/callback?next=${encodeURIComponent(next)}`,
			scopes: PROVIDER_SCOPES[provider]
		}
	});

	if (oauthError || !data.url) {
		/**
		 * Nearly always a configuration fault rather than anything the visitor
		 * did: the provider disabled in the Supabase project, or credentials
		 * that are missing or wrong.
		 */
		console.error(`Could not start ${oauthProviderLabel(provider)} sign-in:`, oauthError?.message);
		redirect(303, '/auth/error?reason=exchange');
	}

	redirect(303, data.url);
};
