import { error, fail } from '@sveltejs/kit';
import {
	approvalInput,
	isIngestionOperator,
	releaseSubmissionInput
} from '$lib/server/ingestion-review';
import { loadFieldContext, loadReviewQueue } from '$lib/server/ingestion-queue';
import type { Json } from '$lib/db.types';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	if (!(await isIngestionOperator(locals.providers.database)))
		error(403, 'Data Steward access required.');
	const loaded = await loadReviewQueue(locals.providers.database, url);
	return { ...loaded, ...(await loadFieldContext(locals.providers.database, url, loaded)) };
};

export const actions: Actions = {
	default: async ({ locals, request }) => {
		if (!(await isIngestionOperator(locals.providers.database)))
			error(403, 'Data Steward access required.');
		const form = await request.formData();
		const intent = form.get('intent');
		if (intent === 'submit_publication') {
			const input = releaseSubmissionInput.safeParse(Object.fromEntries(form));
			if (!input.success)
				return fail(400, { intent, message: 'Choose a release class and provide a reason.' });
			const result = await locals.providers.database.rpc('submit_publication_release', {
				p_release_class: input.data.releaseClass,
				p_items: [{ action: 'publish_change_set', change_set_id: input.data.approval }],
				p_reason: input.data.reason
			});
			if (result.error)
				return fail(result.error.code === '42501' ? 403 : 409, {
					intent,
					message: 'Release was not submitted. Reload the saved approval.'
				});
			return {
				intent,
				releaseId: result.data,
				message: 'Frozen publication release submitted for its required decision.'
			};
		}
		if (intent !== 'approve') return fail(400, { intent, message: 'Unknown field-change action.' });
		let fields: unknown;
		try {
			fields = form.getAll('field').map((value) => JSON.parse(String(value)));
		} catch {
			return fail(400, { intent, message: 'Invalid field selection.' });
		}
		const input = approvalInput.safeParse({ ...Object.fromEntries(form), fields });
		if (!input.success)
			return fail(400, {
				intent,
				message: 'Select eligible fields after saving a matching identity decision.'
			});
		const result = await locals.providers.database.rpc('approve_ingestion_fields', {
			p_run: input.data.run,
			p_version: input.data.version,
			p_revision: input.data.revision,
			p_organisation: input.data.organisation || undefined,
			p_fields: input.data.fields as Json
		});
		if (result.error)
			return fail(result.error.code === '42501' ? 403 : 409, {
				intent,
				message:
					result.error.message === 'Complete enabled source required'
						? 'Approval not saved: the source is paused or the run is incomplete.'
						: 'Approval not saved. Reload and check the identity decision and field revisions.'
			});
		return {
			intent,
			approvalId: result.data,
			message: 'Field approval saved. Submission remains a separate decision.'
		};
	}
};
