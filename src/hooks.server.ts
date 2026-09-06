import { createServerClient } from '@supabase/ssr';
import type { SetAllCookies } from '@supabase/ssr';
import { error, redirect, type Handle } from '@sveltejs/kit';
import { sequence } from '@sveltejs/kit/hooks';

import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import type { Database } from '$lib/db.types';
import type { TypedSupabaseClient } from '$lib/supabase-client';
import { isSiteAdmin } from '$lib/server/authorization';

/**
 * The cron endpoint authenticates with its own shared secret and talks to
 * Supabase with the service role key, so it needs neither a request-scoped
 * client nor a session.
 */
const CRON_PATH = '/api/cron';

/** Paths reachable without a session. Everything else requires one. */
function isPublicPath(pathname: string): boolean {
	return pathname === '/' || pathname === '/auth' || pathname.startsWith('/auth/');
}

/**
 * Paths under `/auth` that stay reachable while signed in: the sign-out flow,
 * the two provider callbacks, the OAuth hand-off, and the error page. The rest
 * of `/auth` is redirected away so a signed-in user does not land on a sign-in
 * form.
 *
 * `/auth/callback` in particular must stay reachable. A stale session cookie
 * can still be present when GitHub returns, and bouncing that request to
 * /organisations would discard the code before it is exchanged.
 */
function isSignedInAuthPath(pathname: string): boolean {
	return (
		pathname.startsWith('/auth/signout') ||
		pathname.startsWith('/auth/confirm') ||
		pathname.startsWith('/auth/callback') ||
		pathname.startsWith('/auth/github') ||
		pathname.startsWith('/auth/error')
	);
}

const supabase: Handle = async ({ event, resolve }) => {
	if (event.url.pathname === CRON_PATH) {
		return await resolve(event);
	}
	/**
	 * Creates a Supabase client specific to this server request.
	 *
	 * The Supabase client gets the Auth token from the request cookies.
	 *
	 * Every table in this project lives in the `community_orgs` schema, so the
	 * schema is pinned here — the default is `public`, which holds none of them.
	 */
	event.locals.supabase = createServerClient<Database, 'community_orgs'>(
		PUBLIC_SUPABASE_URL,
		PUBLIC_SUPABASE_ANON_KEY,
		{
			db: { schema: 'community_orgs' },
			cookies: {
				getAll: () => event.cookies.getAll(),
				/**
				 * SvelteKit's cookies API requires `path` to be explicitly set in
				 * the cookie options. Setting `path` to `/` replicates previous/
				 * standard behavior.
				 */
				setAll: ((cookiesToSet) => {
					cookiesToSet.forEach(({ name, value, options }) => {
						event.cookies.set(name, value, { ...options, path: '/' });
					});
				}) satisfies SetAllCookies
			}
		}
	) as unknown as TypedSupabaseClient;

	/**
	 * Unlike `supabase.auth.getSession()`, which returns the session _without_
	 * validating the JWT, this function also calls `getUser()` to validate the
	 * JWT before returning the session.
	 */
	event.locals.safeGetSession = async () => {
		const {
			data: { session }
		} = await event.locals.supabase.auth.getSession();
		if (!session) {
			return { session: null, user: null };
		}

		const {
			data: { user },
			error: getUserError
		} = await event.locals.supabase.auth.getUser();
		if (getUserError) {
			// JWT validation has failed
			return { session: null, user: null };
		}

		/**
		 * `session.user` here still comes from cookie storage and is wrapped in a
		 * warning proxy that fires the moment any of its properties are read —
		 * which happens the instant this session is serialized into the page data
		 * for hydration. Overwrite it with the copy `getUser()` just validated
		 * against the Auth server before it goes anywhere.
		 */
		return { session: { ...session, user: user! }, user };
	};

	return resolve(event, {
		filterSerializedResponseHeaders(name) {
			/**
			 * Supabase libraries use the `content-range` and `x-supabase-api-version`
			 * headers, so we need to tell SvelteKit to pass it through.
			 */
			return name === 'content-range' || name === 'x-supabase-api-version';
		}
	});
};

/**
 * Requires a validated session for every route outside the public set, and
 * populates `locals.session` / `locals.user` so routes do not each have to call
 * `safeGetSession()` again.
 *
 * This is a coarse gate: it establishes *who* the caller is. Per-organisation
 * permissions are checked in each route via `$lib/server/authorization`, and
 * enforced independently by row-level security in the database.
 */
const authGuard: Handle = async ({ event, resolve }) => {
	if (event.url.pathname === CRON_PATH) {
		return await resolve(event);
	}

	const { session, user } = await event.locals.safeGetSession();
	event.locals.session = session;
	event.locals.user = user;

	const { pathname, search } = event.url;

	if (!session && !isPublicPath(pathname)) {
		const redirectTo = encodeURIComponent(pathname + search);
		redirect(303, `/auth/signin?redirectTo=${redirectTo}`);
	}

	if (session && isPublicPath(pathname) && pathname !== '/' && !isSignedInAuthPath(pathname)) {
		redirect(303, '/organisations');
	}

	/**
	 * `/admin` needs more than a session. Roles in this schema are scoped to an
	 * organisation, so the closest honest mapping for a site-wide area is
	 * "admin or owner of at least one organisation".
	 */
	if (pathname === '/admin' || pathname.startsWith('/admin/')) {
		if (!(await isSiteAdmin(event.locals.supabase, user?.id))) {
			error(403, 'You do not have access to this area.');
		}
	}

	return resolve(event);
};

export const handle: Handle = sequence(supabase, authGuard);
