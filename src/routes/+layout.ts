import { createBrowserClient, createServerClient, isBrowser } from '@supabase/ssr';
import { PUBLIC_SUPABASE_ANON_KEY, PUBLIC_SUPABASE_URL } from '$env/static/public';
import type { Database } from '$lib/db.types';
import type { TypedSupabaseClient } from '$lib/supabase-client';
import type { LayoutLoad } from './$types';

export const load: LayoutLoad = async ({ data, depends, fetch }) => {
	/**
	 * Declare a dependency so the layout can be invalidated, for example, on
	 * session refresh.
	 */
	depends('supabase:auth');
	depends('app:root');

	/**
	 * Every table in this project lives in the `community_orgs` schema, so the
	 * schema is pinned on both clients — the default is `public`, which holds
	 * none of them.
	 */
	const supabase = (isBrowser()
		? createBrowserClient<Database, 'community_orgs'>(
				PUBLIC_SUPABASE_URL,
				PUBLIC_SUPABASE_ANON_KEY,
				{
					db: { schema: 'community_orgs' },
					global: { fetch }
				}
			)
		: createServerClient<Database, 'community_orgs'>(
				PUBLIC_SUPABASE_URL,
				PUBLIC_SUPABASE_ANON_KEY,
				{
					db: { schema: 'community_orgs' },
					global: { fetch },
					cookies: {
						getAll() {
							return data.cookies;
						}
					}
				}
			)) as unknown as TypedSupabaseClient;

	/**
	 * It's fine to use `getSession` here, because on the client, `getSession` is
	 * safe, and on the server, it reads `session` from the `LayoutData`, which
	 * safely checked the session using `safeGetSession`.
	 */
	const {
		data: { session }
	} = await supabase.auth.getSession();

	/**
	 * `data.user` was validated with `getUser()` on the server, so take it from
	 * there rather than making a third auth round-trip per navigation. The
	 * `depends('supabase:auth')` above is what re-runs this load — and the
	 * server load with it — when the session changes.
	 */
	return { session, supabase, user: data.user };
};
