import { error } from '@sveltejs/kit';
import { isSiteAdmin } from '$lib/server/authorization';
import { campaignDashboardSchema } from '$lib/server/campaigns';
import { isIngestionOperator } from '$lib/server/ingestion-review';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	const [canSteward, canAdmin] = await Promise.all([
		isIngestionOperator(locals.supabase),
		isSiteAdmin(locals.supabase, locals.user?.id)
	]);
	if (!canSteward && !canAdmin) error(403, 'Campaign authority required.');
	const result = await locals.supabase.rpc('campaign_dashboard');
	const parsed = campaignDashboardSchema.safeParse(result.data);
	if (result.error || !parsed.success)
		error(result.error?.code === '42501' ? 403 : 500, 'Could not load campaigns.');
	return { campaigns: parsed.data.campaigns };
};
