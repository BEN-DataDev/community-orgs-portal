import { error, fail } from '@sveltejs/kit';
import { z } from 'zod';
import {
	isIngestionOperator,
	validationAttemptInput,
	validationFilterInput,
	validationQueueSchema,
	validationResolutionInput,
	validationRunReadinessSchema
} from '$lib/server/ingestion-review';
import type { Json } from '$lib/db.types';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	if (!(await isIngestionOperator(locals.supabase))) error(403, 'Data Steward access required.');
	const filter = validationFilterInput.safeParse({
		issue: url.searchParams.get('issue') || '',
		run: url.searchParams.get('issue_run') || url.searchParams.get('run') || '',
		release: url.searchParams.get('release') || '',
		category: url.searchParams.get('category') || '',
		decision: url.searchParams.get('issue_decision') || '',
		offset: url.searchParams.get('issue_offset') || 0
	});
	const campaign = url.searchParams.get('campaign') || '';
	if (!filter.success || (campaign && !z.string().uuid().safeParse(campaign).success))
		error(400, 'Invalid validation queue filter.');
	const result = await locals.supabase.rpc('validation_issue_queue', {
		p_issue: filter.data.issue || undefined,
		p_run: filter.data.run || undefined,
		p_release: filter.data.release || undefined,
		p_category: filter.data.category,
		p_decision: filter.data.decision,
		p_offset: filter.data.offset
	});
	const queue = validationQueueSchema.safeParse(result.data);
	if (result.error || !queue.success)
		error(
			result.error?.code === '42501' ? 403 : result.error?.code === 'P0002' ? 404 : 500,
			'Could not load validation issues.'
		);
	let readiness: z.infer<typeof validationRunReadinessSchema> | null = null;
	if (queue.data.detail?.run_id) {
		const response = await locals.supabase.rpc('validation_run_readiness', {
			p_run: queue.data.detail.run_id
		});
		const parsed = validationRunReadinessSchema.safeParse(response.data);
		if (response.error || !parsed.success) error(500, 'Could not load run readiness.');
		readiness = parsed.data;
	}
	return { queue: queue.data, filter: filter.data, readiness, campaign };
};

export const actions: Actions = {
	default: async ({ locals, request }) => {
		if (!(await isIngestionOperator(locals.supabase))) error(403, 'Data Steward access required.');
		const form = await request.formData();
		const intent = form.get('intent');
		if (intent === 'validate_issue') {
			const input = validationAttemptInput.safeParse(Object.fromEntries(form));
			if (!input.success)
				return fail(400, { intent, message: 'Enter a proposed value to validate.' });
			const result = await locals.supabase.rpc('validate_issue_value', {
				p_issue: input.data.issue,
				p_value: input.data.proposed as Json
			});
			if (result.error)
				return fail(result.error.code === '42501' ? 403 : 400, {
					intent,
					message: 'The proposed value could not be validated.'
				});
			const checked = z
				.object({ valid: z.boolean(), message: z.string() })
				.passthrough()
				.safeParse(result.data);
			if (!checked.success)
				return fail(500, { intent, message: 'Unexpected validation response.' });
			return { intent, validationPassed: checked.data.valid, message: checked.data.message };
		}
		if (intent === 'save_resolution') {
			const input = validationResolutionInput.safeParse(Object.fromEntries(form));
			if (!input.success)
				return fail(400, { intent, message: 'Choose an allowed decision and provide a note.' });
			const result = await locals.supabase.rpc('save_validation_resolution', {
				p_issue: input.data.issue,
				p_revision: input.data.revision,
				p_decision: input.data.decision,
				p_proposed_value:
					input.data.decision === 'correct' ? (input.data.proposed as Json) : undefined,
				p_note: input.data.note,
				p_evidence_reference: input.data.evidence || undefined
			});
			if (result.error)
				return fail(
					result.error.code === '40001' ? 409 : result.error.code === '42501' ? 403 : 400,
					{
						intent,
						message:
							result.error.code === '40001'
								? 'Another steward changed this resolution. Reload before saving.'
								: 'Resolution was not saved. Validate the value and permitted action.'
					}
				);
			return { intent, message: 'Resolution saved. Original source evidence is unchanged.' };
		}
		if (intent === 'create_corrected_run') {
			const run = z
				.string()
				.regex(/^[1-9][0-9]*$/)
				.safeParse(form.get('run'));
			if (!run.success) return fail(400, { intent, message: 'Invalid parent run.' });
			const result = await locals.supabase.rpc('create_corrected_run', { p_run: run.data });
			if (result.error)
				return fail(
					result.error.code === '40001' ? 409 : result.error.code === '42501' ? 403 : 400,
					{ intent, message: result.error.message }
				);
			return {
				intent,
				replayId: result.data,
				message: 'Corrected run queued for the Data Steward.'
			};
		}
		return fail(400, { intent, message: 'Unknown validation action.' });
	}
};
