import { error, fail } from '@sveltejs/kit';
import { isIngestionOperator, queueSchema, reviewInput } from '$lib/server/ingestion-review';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	if (!(await isIngestionOperator(locals.supabase)))
		error(403, 'Ingestion operator access required.');
	const run = url.searchParams.get('run') || undefined;
	const version = url.searchParams.get('version') || undefined;
	const offset = Number(url.searchParams.get('offset') || 0);
	const search = url.searchParams.get('search') || '';
	if (
		[run, version].some((x) => x && !/^[1-9][0-9]{0,18}$/.test(x)) ||
		!Number.isInteger(offset) ||
		offset < 0 ||
		offset > 1000000 ||
		search.length > 100
	)
		error(400, 'Invalid review filter.');
	const result = await locals.supabase.rpc('ingestion_review_queue', {
		p_run: run,
		p_version: version,
		p_offset: offset,
		p_search: search
	});
	if (result.error)
		error(
			result.error.code === 'P0002' ? 404 : result.error.code === '42501' ? 403 : 500,
			'Could not load import review.'
		);
	const parsed = queueSchema.safeParse(result.data);
	if (!parsed.success) error(500, 'Unexpected import review response.');
	return { queue: parsed.data, offset, search };
};
export const actions: Actions = {
	default: async ({ locals, request }) => {
		if (!(await isIngestionOperator(locals.supabase)))
			error(403, 'Ingestion operator access required.');
		const parsed = reviewInput.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success)
			return fail(400, {
				message: 'Choose a decision, provide a note and select an organisation only when linking.'
			});
		const x = parsed.data;
		const { error: problem } = await locals.supabase.rpc('save_ingestion_review', {
			p_run: x.run,
			p_version: x.version,
			p_revision: x.revision,
			p_decision: x.decision,
			p_organisation: x.organisation || undefined,
			p_note: x.note
		});
		if (problem)
			return fail(problem.code === '40001' ? 409 : problem.code === '42501' ? 403 : 400, {
				message:
					problem.code === '40001'
						? 'Another operator changed this review. Reload and compare before saving again.'
						: 'Review could not be saved. Reload and check the selected record.'
			});
		return { message: 'Review saved. Publication requires a separate step.' };
	}
};
