import { json } from '@sveltejs/kit';
import { createHash, timingSafeEqual } from 'node:crypto';
import { PUBLIC_SUPABASE_URL } from '$env/static/public';
import { PRIVATE_SUPABASE_SERVICE_ROLE_KEY } from '$env/static/private';
import { env } from '$env/dynamic/private';
import type { RequestHandler } from './$types';
import { createClient } from '@supabase/supabase-js';

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

	if (!PUBLIC_SUPABASE_URL || !PRIVATE_SUPABASE_SERVICE_ROLE_KEY) {
		console.error('Cron database credentials are not configured.');
		return new Response('Service Unavailable', { status: 503 });
	}

	try {
		// Create the privileged client only after authenticating the request.
		// health_check lives in public, outside the generated community_orgs types.
		const supabase = createClient(PUBLIC_SUPABASE_URL, PRIVATE_SUPABASE_SERVICE_ROLE_KEY, {
			auth: { persistSession: false, autoRefreshToken: false }
		});
		const { data, error } = await supabase.rpc('health_check');
		if (error) {
			console.error('Cron health check failed:', error);
			return json({ success: false, stage: 'health_check' }, { status: 500 });
		}

		const { data: purged, error: purgeError } = await supabase
			.schema('community_orgs')
			.rpc('purge_stale_anonymous_users');
		if (purgeError) {
			console.error('Cron guest cleanup failed:', purgeError);
			return json({ success: false, stage: 'guest_cleanup' }, { status: 500 });
		}

		const { data: abandoned, error: abandonedError } = await supabase
			.schema('community_orgs')
			.rpc('abandoned_account_avatars');
		if (abandonedError) return json({ success: false, stage: 'avatar_cleanup' }, { status: 500 });
		if (abandoned?.length) {
			const { error: cleanupError } = await supabase.storage
				.from('avatars')
				.remove(abandoned.map((row: { path: string }) => row.path));
			if (cleanupError) return json({ success: false, stage: 'avatar_cleanup' }, { status: 500 });
		}

		console.info('Cron completed:', {
			completedAt: new Date().toISOString(),
			purgedAnonymousUsers: purged
		});
		return json({ success: true, data, purgedAnonymousUsers: purged });
	} catch (error) {
		console.error('Cron execution failed:', error);
		return json({ success: false, stage: 'execution' }, { status: 500 });
	}
};
