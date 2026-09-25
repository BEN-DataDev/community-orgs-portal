import { json } from '@sveltejs/kit';
import { createHash, timingSafeEqual } from 'node:crypto';
import { PUBLIC_SUPABASE_URL } from '$env/static/public';
import { PRIVATE_SUPABASE_SERVICE_ROLE_KEY } from '$env/static/private';
import { env } from '$env/dynamic/private';
import type { RequestHandler } from './$types';
import { createClient } from '@supabase/supabase-js';
import type { Database } from '$lib/db.types';
import type { TypedSupabaseClient } from '$lib/supabase-client';
import { PortalIdentityError, requirePortalIdentity } from '$lib/server/portal';
import {
	ProviderMaintenanceError,
	SupabaseDomainDatabase,
	SupabaseMaintenanceProvider
} from '$lib/server/providers/supabase';

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
		const supabase = createClient<Database>(
			PUBLIC_SUPABASE_URL,
			PRIVATE_SUPABASE_SERVICE_ROLE_KEY,
			{
				auth: { persistSession: false, autoRefreshToken: false }
			}
		);
		const domain = new SupabaseDomainDatabase(
			supabase.schema('community_orgs') as unknown as TypedSupabaseClient
		);
		let portal;
		try {
			portal = await requirePortalIdentity(domain);
		} catch (error) {
			if (error instanceof PortalIdentityError) {
				console.error('Cron portal identity check failed:', error.message);
				return json({ success: false, stage: 'portal_identity' }, { status: 503 });
			}
			throw error;
		}
		let maintenance;
		try {
			maintenance = await new SupabaseMaintenanceProvider(supabase).run();
		} catch (error) {
			if (error instanceof ProviderMaintenanceError) {
				console.error(`Cron ${error.stage} failed:`, error.failure);
				return json({ success: false, stage: error.stage }, { status: 500 });
			}
			throw error;
		}

		console.info('Cron completed:', {
			completedAt: new Date().toISOString(),
			purgedAnonymousUsers: maintenance.purgedAnonymousUsers
		});
		return json({
			success: true,
			data: maintenance.health,
			portal: {
				portalId: portal.portalId,
				portalKey: portal.portalKey,
				lifecycleState: portal.lifecycleState,
				configurationRevision: portal.configurationRevision,
				schemaVersion: portal.schemaVersion,
				scopeRevisionId: portal.scopeRevisionId,
				scopeRevision: portal.scopeRevision,
				scopePostcodes: portal.scopePostcodes
			},
			purgedAnonymousUsers: maintenance.purgedAnonymousUsers,
			acquisitions: maintenance.acquisitions
		});
	} catch (error) {
		console.error('Cron execution failed:', error);
		return json({ success: false, stage: 'execution' }, { status: 500 });
	}
};
