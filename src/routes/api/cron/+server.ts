import { json } from '@sveltejs/kit';
import { createHash, timingSafeEqual } from 'node:crypto';
import { PUBLIC_SUPABASE_URL } from '$env/static/public';
import { PRIVATE_SUPABASE_SERVICE_ROLE_KEY } from '$env/static/private';
import { env } from '$env/dynamic/private';
import type { RequestHandler } from './$types';
import { createClient } from '@supabase/supabase-js';

/**
 * This client uses the service role key, so it bypasses RLS entirely. It is
 * deliberately left untyped: `health_check` lives outside the `community_orgs`
 * schema that `db.types.ts` is generated from.
 */
const supabase = createClient(PUBLIC_SUPABASE_URL, PRIVATE_SUPABASE_SERVICE_ROLE_KEY);

/**
 * Compares two secrets without leaking their contents through timing. Both
 * sides are hashed first so the buffers are always the same length —
 * `timingSafeEqual` throws on a length mismatch.
 */
function secretMatches(provided: string, expected: string): boolean {
	const a = createHash('sha256').update(provided).digest();
	const b = createHash('sha256').update(expected).digest();
	return timingSafeEqual(a, b);
}

export const GET: RequestHandler = async ({ request }) => {
	const cronSecret = env.CRON_SECRET;

	/**
	 * Fail closed. Interpolating an unset variable would compare against the
	 * literal string 'Bearer undefined', which any caller can send.
	 */
	if (!cronSecret) {
		console.error('CRON_SECRET is not configured; refusing to run the health check.');
		return new Response('Service Unavailable', { status: 503 });
	}

	const authHeader = request.headers.get('authorization');
	if (!authHeader || !secretMatches(authHeader, `Bearer ${cronSecret}`)) {
		return new Response('Unauthorized', { status: 401 });
	}

	const { data, error } = await supabase.rpc('health_check');

	if (error) {
		console.error('Health check failed:', error);
		return json({ success: false, error }, { status: 500 });
	}

	/**
	 * Guest sessions leave rows in auth.users that nobody can ever sign back in
	 * as, and they only accumulate. The function is SECURITY DEFINER and granted
	 * to service_role alone, so this endpoint does not need direct access to the
	 * auth schema.
	 *
	 * A failure here is reported but does not fail the request: the health check
	 * above is the part a monitor is watching, and housekeeping that misses a run
	 * catches up on the next one.
	 */
	const { data: purged, error: purgeError } = await supabase
		.schema('community_orgs')
		.rpc('purge_stale_anonymous_users');

	if (purgeError) {
		console.error('Purging stale anonymous users failed:', purgeError);
	}

	return json({ success: true, data, purgedAnonymousUsers: purged ?? null });
};
