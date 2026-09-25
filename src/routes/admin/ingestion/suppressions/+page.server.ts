import { error, fail } from '@sveltejs/kit';
import { isIngestionOperator, suppressionInput } from '$lib/server/ingestion-review';
import { loadReviewQueue, loadSuppressionContext } from '$lib/server/ingestion-queue';
import type { Json } from '$lib/db.types';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	if (!(await isIngestionOperator(locals.providers.database)))
		error(403, 'Data Steward access required.');
	const loaded = await loadReviewQueue(locals.providers.database, url);
	return { ...loaded, ...(await loadSuppressionContext(locals.providers.database, url, loaded)) };
};

export const actions: Actions = {
	default: async ({ locals, request }) => {
		if (!(await isIngestionOperator(locals.providers.database)))
			error(403, 'Data Steward access required.');
		const form = await request.formData();
		let expected: unknown;
		try {
			expected = JSON.parse(String(form.get('expected')));
		} catch {
			return fail(400, { message: 'Invalid withdrawal preview.' });
		}
		const input = suppressionInput.safeParse({ ...Object.fromEntries(form), expected });
		if (!input.success)
			return fail(400, { message: 'Choose a scope, provide a reason and confirm removal.' });
		const result = await locals.providers.database.rpc('submit_publication_release', {
			p_release_class: 'suppression',
			p_items: [
				{
					action: 'suppress_content',
					run: input.data.run,
					version: input.data.version,
					field: input.data.field,
					reason: input.data.reason,
					expected: input.data.expected
				}
			] as Json,
			p_reason: input.data.reason
		});
		if (result.error)
			return fail(result.error.code === '42501' ? 403 : 409, {
				message: 'Suppression was not submitted. Reload; the target may have changed.'
			});
		return {
			releaseId: result.data,
			message: 'Suppression release submitted. A different authorised person must approve it.'
		};
	}
};
