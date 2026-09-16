import { error, fail } from '@sveltejs/kit';
import { z } from 'zod';
import { isSiteAdmin } from '$lib/server/authorization';
import { publicSourceUrl } from '$lib/server/source-attribution';
import type { Actions, PageServerLoad } from './$types';

const sourcesSchema = z.array(
	z.object({
		source_id: z.string(),
		resource_id: z.string(),
		enabled: z.boolean(),
		token: z.string(),
		metadata: z.record(z.unknown()),
		runs: z.array(
			z.object({
				id: z.string(),
				run_key: z.string(),
				completion: z.string(),
				observed_at: z.string()
			})
		),
		history: z.array(
			z.object({
				enabled: z.boolean(),
				reason: z.string(),
				changed_at: z.string(),
				changed_by: z.string()
			})
		)
	})
);
export const load: PageServerLoad = async ({ locals, setHeaders, url }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	if (!(await isSiteAdmin(locals.supabase, locals.user?.id)))
		error(403, 'Platform administrator required.');
	const result = await locals.supabase.rpc('ingestion_source_approvals');
	if (result.error) error(500, 'Could not load source approvals.');
	const parsed = sourcesSchema.safeParse(result.data);
	if (!parsed.success) error(500, 'Unexpected source approval response.');
	const run = url.searchParams.get('run') ?? '';
	const version = url.searchParams.get('version') ?? '';
	if ([run, version].some((v) => v && !/^[1-9][0-9]{0,18}$/.test(v)))
		error(400, 'Invalid review reference.');
	return {
		run,
		version,
		sources: parsed.data.map((s) => ({
			...s,
			url: publicSourceUrl(
				typeof s.metadata.public_url === 'string' ? s.metadata.public_url : null
			),
			licenceUrl: publicSourceUrl(
				typeof s.metadata.public_licence_url === 'string' ? s.metadata.public_licence_url : null
			)
		}))
	};
};
export const actions: Actions = {
	default: async ({ locals, request }) => {
		if (!(await isSiteAdmin(locals.supabase, locals.user?.id)))
			error(403, 'Platform administrator required.');
		const parsed = z
			.object({
				source: z.string().min(1),
				resource: z.string().min(1),
				enabled: z.enum(['true', 'false']),
				token: z.string().regex(/^[a-f0-9]{32}$/),
				reason: z.string().trim().min(1).max(2000),
				confirm: z.literal('yes')
			})
			.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success)
			return fail(400, { message: 'Enter a reason and confirm the source status change.' });
		const x = parsed.data;
		const result = await locals.supabase.rpc('set_ingestion_source_enabled', {
			p_source: x.source,
			p_resource: x.resource,
			p_enabled: x.enabled === 'true',
			p_token: x.token,
			p_reason: x.reason
		});
		if (result.error)
			return fail(result.error.code === '42501' ? 403 : 409, {
				message:
					result.error.code === '40001'
						? 'Source changed. Reload this page and review the latest details before saving.'
						: 'Source status was not saved. Reload and try again.'
			});
		return {
			message:
				x.enabled === 'true'
					? 'Source enabled. Return to import review to save field approval.'
					: 'Source paused. New imports, field approvals and publications are blocked.'
		};
	}
};
