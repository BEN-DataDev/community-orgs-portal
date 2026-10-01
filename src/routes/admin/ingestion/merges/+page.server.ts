import { error, fail } from '@sveltejs/kit';
import {
	seedMergeDecisionInput,
	seedMergeFilter,
	seedMergeQueueSchema
} from '$lib/server/ingestion-review';
import type { Actions, PageServerLoad } from './$types';

const PAGE_SIZE = 25;

export const load: PageServerLoad = async ({ locals, url, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	if (!(await locals.isIngestionOperator())) error(403, 'Data Steward access required.');
	const filter = seedMergeFilter.parse(Object.fromEntries(url.searchParams));
	const result = await locals.providers.database.rpc('seed_merge_review_queue', {
		p_status: filter.status,
		p_method: filter.method,
		p_offset: filter.offset,
		p_limit: PAGE_SIZE
	});
	const parsed = seedMergeQueueSchema.safeParse(result.data);
	if (result.error || !parsed.success)
		error(result.error?.code === '42501' ? 403 : 500, 'Could not load merge reviews.');
	return { ...parsed.data, filter, pageSize: PAGE_SIZE };
};

export const actions: Actions = {
	default: async ({ locals, request }) => {
		if (!(await locals.isIngestionOperator())) error(403, 'Data Steward access required.');
		const parsed = seedMergeDecisionInput.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success)
			return fail(400, {
				source: null,
				message: 'Choose a decision. A split needs a note explaining the difference.'
			});
		const input = parsed.data;
		const result = await locals.providers.database.rpc('review_seed_merge', {
			p_source: input.source,
			p_decision: input.decision,
			p_note: input.note || undefined
		});
		if (result.error) {
			const code = result.error.code;
			return fail(code === '42501' ? 403 : code === '40001' ? 409 : code === '55000' ? 409 : 400, {
				source: input.source,
				message:
					code === '40001'
						? 'Another steward already reviewed this merge. Reload the queue.'
						: code === '55000'
							? 'This merge changed after the correction, so it cannot be reviewed here. Resolve it on the organisation or in identity review.'
							: 'The decision was not saved.'
			});
		}
		return {
			source: input.source,
			message:
				input.decision === 'split'
					? 'Split saved. The NSW association is a separate organisation again.'
					: 'Merge confirmed.'
		};
	}
};
