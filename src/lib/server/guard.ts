import { needsMfaChallenge, type SessionAal } from '$lib/auth/session';

/**
 * The routing half of the auth guard, as a pure function.
 *
 * This used to be a run of `if` statements inside `hooks.server.ts`. Four
 * interacting conditions — public paths, paths that stay open while signed in,
 * guest sessions and pending MFA challenges — is more than that shape can carry
 * legibly, and a wrong answer here is either a lockout or an open door. Keeping
 * it free of `event` and of anything async means it can be reasoned about, and
 * tested, on its own.
 *
 * Returns the path to redirect to, or `null` to let the request through.
 */

function isAuthPath(pathname: string): boolean {
	return pathname === '/auth' || pathname.startsWith('/auth/');
}

/** Requests reachable without a session. Everything else requires one. */
export function isPublicPath(pathname: string, method = 'GET'): boolean {
	if (pathname === '/' || isAuthPath(pathname)) return true;
	// Public browsing still relies on row-level security to exclude private organisations.
	return (
		(method === 'GET' || method === 'HEAD') &&
		/^\/organisations(?:\/[^/]+(?:\/(?:contact|legal|finance|operations|relationships|history))?)?\/?$/.test(
			pathname
		)
	);
}

/**
 * Paths under `/auth` that stay reachable while signed in: the sign-out flow,
 * both callbacks, the OAuth hand-off, the recovery and challenge screens, and
 * the error page. The rest of `/auth` is redirected away so a signed-in user
 * does not land on a sign-in form.
 *
 * `/auth/callback` in particular must stay reachable. A stale session cookie can
 * still be present when the provider returns, and bouncing that request to
 * /organisations would discard the code before it is exchanged.
 *
 * `/auth/reset-password` is here for a related reason: verifying a recovery link
 * establishes a real session, so without this entry the guard would bounce the
 * user away before they could set a password — the thing they clicked the link
 * to do.
 */
export function isSignedInAuthPath(pathname: string): boolean {
	return (
		pathname.startsWith('/auth/signout') ||
		pathname.startsWith('/auth/confirm') ||
		pathname.startsWith('/auth/callback') ||
		pathname.startsWith('/auth/oauth') ||
		pathname.startsWith('/auth/reset-password') ||
		pathname === '/auth/forgot-password' ||
		pathname === '/auth/email-change' ||
		pathname.startsWith('/auth/mfa') ||
		pathname.startsWith('/auth/error')
	);
}

export interface GuardState {
	pathname: string;
	search: string;
	method?: string;
	hasSession: boolean;
	isAnonymous: boolean;
	aal: SessionAal | null;
}

export function guardRedirect({
	pathname,
	search,
	method = 'GET',
	hasSession,
	isAnonymous,
	aal
}: GuardState): string | null {
	const signInWithReturn = () => `/auth/signin?redirectTo=${encodeURIComponent(pathname + search)}`;

	if (!hasSession) {
		return isPublicPath(pathname, method) ? null : signInWithReturn();
	}

	const mfaPending = needsMfaChallenge(aal);

	/**
	 * A guest keeps full access to `/auth`. Upgrading to a real account means
	 * reaching the sign-up form or an OAuth button, and the "already signed in,
	 * go away" rule below would otherwise slam that door on the one set of users
	 * who most need it open.
	 */
	if (isAnonymous) {
		/**
		 * Account/admin pages and email-bound invitations cannot do anything
		 * useful for an account with no email and no password. Sent to sign-up
		 * rather than shown a 403, because signing up is what makes them work.
		 */
		if (
			pathname.startsWith('/account') ||
			pathname.startsWith('/admin') ||
			pathname.startsWith('/invitations')
		) {
			return signInWithReturn();
		}
		return null;
	}

	if (isAuthPath(pathname) && !isSignedInAuthPath(pathname)) {
		/**
		 * Straight to the challenge rather than to /organisations, which would
		 * only bounce again on the next request.
		 */
		return mfaPending ? '/auth/mfa' : '/organisations';
	}

	/**
	 * A factor is enrolled but has not been satisfied this session. Row-level
	 * security is what actually withholds the data; this redirect is so the user
	 * gets the code prompt instead of a page full of nothing.
	 *
	 * `/auth` is exempt: the challenge screen lives there, and so does the way
	 * out for someone who cannot complete it.
	 */
	if (mfaPending && pathname !== '/' && !isAuthPath(pathname)) {
		return `/auth/mfa?redirectTo=${encodeURIComponent(pathname + search)}`;
	}

	return null;
}
