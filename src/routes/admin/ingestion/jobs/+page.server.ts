import { error, fail } from '@sveltejs/kit';
import { z } from 'zod';
import { isIngestionOperator } from '$lib/server/ingestion-review';
import { isSiteAdmin } from '$lib/server/authorization';
import type { Actions, PageServerLoad } from './$types';

const dashboard = z.object({
	sources: z.array(
		z.object({
			resource_id: z.string(),
			enabled: z.boolean(),
			title: z.string(),
			postcodes: z.array(z.string().regex(/^[0-9]{4}$/)).nullable(),
			licence_title: z.string(),
			interval_hours: z.number().nullable(),
			next_due_at: z.string().nullable(),
			revision: z.string()
		})
	),
	jobs: z.array(
		z.object({
			id: z.string(),
			resource_id: z.string(),
			status: z.enum(['queued', 'running', 'complete', 'partial', 'failed', 'cancelled']),
			origin: z.string(),
			attempts: z.number(),
			created_at: z.string(),
			available_at: z.string(),
			lease_until: z.string().nullable(),
			finished_at: z.string().nullable(),
			run_id: z.string().nullable(),
			message: z.string().nullable(),
			acquired: z.boolean()
		})
	)
});
export const load: PageServerLoad = async ({ locals, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	if (!(await isIngestionOperator(locals.supabase))) error(403, 'Ingestion operator required.');
	const result = await locals.supabase.rpc('acquisition_dashboard');
	if (result.error) error(500, 'Could not load acquisition jobs.');
	const parsed = dashboard.safeParse(result.data);
	if (!parsed.success) error(500, 'Unexpected acquisition response.');
	return { ...parsed.data, canConfigure: await isSiteAdmin(locals.supabase, locals.user?.id) };
};
export const actions: Actions = {
	run: async ({ locals, request }) => {
		if (!(await isIngestionOperator(locals.supabase))) error(403, 'Ingestion operator required.');
		const input = z
			.object({ resource: z.string().uuid() })
			.safeParse(Object.fromEntries(await request.formData()));
		if (!input.success) return fail(400, { message: 'Choose a configured ACNC resource.' });
		const result = await locals.supabase.rpc('enqueue_acnc_acquisition', {
			p_resource: input.data.resource
		});
		if (result.error)
			return fail(result.error.code === '42501' ? 403 : 409, {
				message:
					'Could not queue acquisition. Check source enablement and configuration, then reload.'
			});
		return {
			message:
				'Acquisition queued. An existing active job is reused. Refresh this page to see progress.'
		};
	},
	configure: async ({ locals, request }) => {
		if (!(await isSiteAdmin(locals.supabase, locals.user?.id)))
			error(403, 'Platform administrator required.');
		const formData = Object.fromEntries(await request.formData());
		const postcodes = String(formData.postcodes ?? '')
			.split(/[\s,]+/)
			.filter(Boolean);
		const input = z
			.object({
				resource: z.string().uuid(),
				licence: z.string().trim().min(1).max(300),
				interval: z.enum(['off', '24', '168', '720']),
				revision: z.string().regex(/^[0-9]{1,19}$/)
			})
			.safeParse(formData);
		const canonicalPostcodes = [...new Set(postcodes)].sort();
		if (
			!input.success ||
			postcodes.length !== canonicalPostcodes.length ||
			canonicalPostcodes.length < 1 ||
			canonicalPostcodes.length > 50 ||
			canonicalPostcodes.some((postcode) => !/^[0-9]{4}$/.test(postcode))
		)
			return fail(400, {
				message: 'Enter 1 to 50 unique four-digit postcodes, a reviewed licence title and schedule.'
			});
		const x = input.data;
		const result = await locals.supabase.rpc('configure_acnc_acquisition', {
			p_resource: x.resource,
			p_postcodes: canonicalPostcodes,
			p_licence: x.licence,
			p_interval: x.interval === 'off' ? null : Number(x.interval),
			p_revision: x.revision
		});
		if (result.error)
			return fail(result.error.code === '42501' ? 403 : 409, {
				message: 'Configuration was not saved. Reload to check the latest configuration and source.'
			});
		return {
			message:
				'Configuration saved. Previous active jobs were cancelled. You can now queue a fresh acquisition.'
		};
	}
};
