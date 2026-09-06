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

/** Paths reachable without a session. Everything else requires one. */
export function isPublicPath(pathname: string): boolean {
	return pathname === '/' || pathname === '/auth' || pathname.startsWith('/auth/');
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
		pathname.startsWith('/auth/mfa') ||
		pathname.startsWith('/auth/error')
	);
}

export interface GuardState {
	pathname: string;
	search: string;
	hasSession: boolean;
	isAnonymous: boolean;
	aal: SessionAal | null;
}

export function guardRedirect({
	pathname,
	search,
	hasSession,
	isAnonymous,
	aal
}: GuardState): string | null {
	const signInWithReturn = () => `/auth/signin?redirectTo=${encodeURIComponent(pathname + search)}`;

	if (!hasSession) {
		return isPublicPath(pathname) ? null : signInWithReturn();
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
		 * Nothing under `/account` or `/admin` can do anything useful for an
		 * account with no email and no password. Sent to sign-up rather than
		 * shown a 403, because signing up is what would make the page work.
		 */
		if (pathname.startsWith('/account') || pathname.startsWith('/admin')) {
			return signInWithReturn();
		}
		return null;
	}

	if (isPublicPath(pathname) && pathname !== '/' && !isSignedInAuthPath(pathname)) {
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
	if (mfaPending && !isPublicPath(pathname)) {
		return `/auth/mfa?redirectTo=${encodeURIComponent(pathname + search)}`;
	}

	return null;
}
