import { error, fail } from '@sveltejs/kit';
import { isIngestionOperator, reviewInput } from '$lib/server/ingestion-review';
import { loadReviewQueue } from '$lib/server/ingestion-queue';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	if (!(await isIngestionOperator(locals.supabase))) error(403, 'Data Steward access required.');
	return loadReviewQueue(locals.supabase, url);
};

export const actions: Actions = {
	default: async ({ locals, request }) => {
		if (!(await isIngestionOperator(locals.supabase))) error(403, 'Data Steward access required.');
		const parsed = reviewInput.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success)
			return fail(400, {
				message: 'Choose a decision, provide a note and select an organisation only when linking.'
			});
		const input = parsed.data;
		const result = await locals.supabase.rpc('save_ingestion_review', {
			p_run: input.run,
			p_version: input.version,
			p_revision: input.revision,
			p_decision: input.decision,
			p_organisation: input.organisation || undefined,
			p_note: input.note
		});
		if (result.error)
			return fail(result.error.code === '40001' ? 409 : result.error.code === '42501' ? 403 : 400, {
				message:
					result.error.code === '40001'
						? 'Another steward changed this review. Reload before saving.'
						: 'Review could not be saved. Check the selected record.'
			});
		return {
			message: 'Identity and eligibility decision saved. Field changes remain a separate decision.'
		};
	}
};
