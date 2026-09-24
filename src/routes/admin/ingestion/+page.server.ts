import { z } from 'zod';
import { error, fail } from '@sveltejs/kit';
import {
	isIngestionOperator,
	queueSchema,
	reviewInput,
	fieldPreviewSchema,
	approvalsSchema,
	approvalInput,
	releaseSubmissionInput,
	withdrawalSchema,
	suppressionInput,
	validationQueueSchema,
	validationRunReadinessSchema,
	validationFilterInput,
	validationAttemptInput,
	validationResolutionInput
} from '$lib/server/ingestion-review';
import type { Json } from '$lib/db.types';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	if (!(await isIngestionOperator(locals.supabase)))
		error(403, 'Ingestion operator access required.');
	const run = url.searchParams.get('run') || undefined;
	const version = url.searchParams.get('version') || undefined;
	const offset = Number(url.searchParams.get('offset') || 0);
	const search = url.searchParams.get('search') || '';
	const validationFilter = validationFilterInput.safeParse({
		issue: url.searchParams.get('issue') || '',
		run: url.searchParams.get('issue_run') || '',
		release: url.searchParams.get('release') || '',
		category: url.searchParams.get('category') || '',
		decision: url.searchParams.get('issue_decision') || '',
		offset: url.searchParams.get('issue_offset') || 0
	});
	if (!validationFilter.success) error(400, 'Invalid validation issue filter.');
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
	let preview = null;
	let withdrawal: z.infer<typeof withdrawalSchema> | null = null;
	let withdrawalFields: z.infer<typeof fieldPreviewSchema>['fields'] = [];
	let approvals: z.infer<typeof approvalsSchema> = [];
	if (parsed.data.detail && parsed.data.run) {
		const target =
			url.searchParams.get('target') ??
			parsed.data.detail.review?.organisation_id ??
			parsed.data.detail.identity_match?.organisation_id ??
			parsed.data.detail.linked_organisation_id ??
			'';
		if (target && !z.string().uuid().safeParse(target).success)
			error(400, 'Invalid preview organisation.');
		const result = await locals.supabase.rpc('ingestion_field_preview', {
			p_run: parsed.data.run,
			p_version: parsed.data.detail.id,
			p_organisation: target || undefined
		});
		if (result.error)
			error(
				result.error.code === '42501' ? 403 : result.error.code === 'P0002' ? 404 : 500,
				'Could not load field preview.'
			);
		const decoded = fieldPreviewSchema.safeParse(result.data);
		if (!decoded.success) error(500, 'Unexpected field preview response.');
		preview = decoded.data;
		const saved = await locals.supabase.rpc('ingestion_field_approvals', {
			p_version: parsed.data.detail.id
		});
		const checked = approvalsSchema.safeParse(saved.data);
		if (saved.error || !checked.success) error(500, 'Could not load field approvals.');
		approvals = checked.data;
		const status = await locals.supabase.rpc('ingestion_withdrawal_status', {
			p_version: parsed.data.detail.id
		});
		const w = withdrawalSchema.safeParse(status.data);
		if (status.error || !w.success) error(500, 'Could not load withdrawal status.');
		withdrawal = w.data;
		withdrawalFields = preview.fields;
		if (withdrawal.organisation_id) {
			if (preview.organisation_id === withdrawal.organisation_id) withdrawalFields = preview.fields;
			else {
				const target = await locals.supabase.rpc('ingestion_field_preview', {
					p_run: parsed.data.run,
					p_version: parsed.data.detail.id,
					p_organisation: withdrawal.organisation_id
				});
				const fields = fieldPreviewSchema.safeParse(target.data);
				if (target.error || !fields.success) error(500, 'Could not load withdrawal target.');
				withdrawalFields = fields.data.fields;
			}
		}
	}
	const vf = validationFilter.data;
	const validationResult = await locals.supabase.rpc('validation_issue_queue', {
		p_issue: vf.issue || undefined,
		p_run: vf.run || undefined,
		p_release: vf.release || undefined,
		p_category: vf.category,
		p_decision: vf.decision,
		p_offset: vf.offset
	});
	const validation = validationQueueSchema.safeParse(validationResult.data);
	if (validationResult.error || !validation.success)
		error(
			validationResult.error?.code === '42501'
				? 403
				: validationResult.error?.code === 'P0002'
					? 404
					: 500,
			'Could not load validation issues.'
		);
	let validationReadiness: z.infer<typeof validationRunReadinessSchema> | null = null;
	if (validation.data.detail?.run_id) {
		const readinessResult = await locals.supabase.rpc('validation_run_readiness', {
			p_run: validation.data.detail.run_id
		});
		const readiness = validationRunReadinessSchema.safeParse(readinessResult.data);
		if (readinessResult.error || !readiness.success)
			error(readinessResult.error?.code === '42501' ? 403 : 500, 'Could not load run readiness.');
		validationReadiness = readiness.data;
	}
	return {
		queue: parsed.data,
		offset,
		search,
		preview,
		approvals,
		withdrawal,
		withdrawalFields,
		validation: validation.data,
		validationReadiness,
		validationFilter: vf
	};
};
export const actions: Actions = {
	default: async ({ locals, request }) => {
		if (!(await isIngestionOperator(locals.supabase)))
			error(403, 'Ingestion operator access required.');
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
			const x = input.data;
			const result = await locals.supabase.rpc('save_validation_resolution', {
				p_issue: x.issue,
				p_revision: x.revision,
				p_decision: x.decision,
				p_proposed_value: x.decision === 'correct' ? (x.proposed as Json) : undefined,
				p_note: x.note,
				p_evidence_reference: x.evidence || undefined
			});
			if (result.error)
				return fail(
					result.error.code === '40001' ? 409 : result.error.code === '42501' ? 403 : 400,
					{
						intent,
						message:
							result.error.code === '40001'
								? 'Another operator changed this resolution. Reload and compare before saving.'
								: 'Resolution was not saved. Validate the value and check the permitted actions.'
					}
				);
			return {
				intent,
				message: 'Resolution saved. The source evidence and original run are unchanged.'
			};
		}
		if (intent === 'create_corrected_run') {
			const run = z
				.string()
				.regex(/^[1-9][0-9]*$/)
				.safeParse(form.get('run'));
			if (!run.success) return fail(400, { intent, message: 'Invalid parent run.' });
			const result = await locals.supabase.rpc('create_corrected_run', { p_run: run.data });
			if (result.error) {
				const knownMessage = {
					'Raw evidence expired':
						'Corrected run was not queued because its raw evidence has expired.',
					'Acquisition failures require a new acquisition':
						'Corrected run was not queued because acquisition failures require a new acquisition.',
					'No validation issues exist for this run':
						'Corrected run was not queued because this run has no validation issues.',
					'Blocking issues remain unresolved or non-overridable':
						'Corrected run was not queued because blocking issues still require action.',
					'A corrected run is already queued': 'A corrected run is already queued.',
					'A corrected run already completed for these resolutions':
						'A corrected run already completed for these resolutions.'
				}[result.error.message];
				return fail(
					result.error.code === '40001' ? 409 : result.error.code === '42501' ? 403 : 400,
					{
						intent,
						message:
							knownMessage ?? 'Corrected run was not queued. Reload and review its readiness.'
					}
				);
			}
			return {
				intent,
				replayId: result.data,
				message:
					'Corrected run queued. The worker will revalidate all retained records into a separate private run.'
			};
		}
		if (intent === 'submit_suppression') {
			let expected: unknown;
			try {
				expected = JSON.parse(String(form.get('expected')));
			} catch {
				return fail(400, { message: 'Invalid withdrawal preview.' });
			}
			const input = suppressionInput.safeParse({ ...Object.fromEntries(form), expected });
			if (!input.success)
				return fail(400, { message: 'Choose a scope, provide a reason and confirm removal.' });
			const x = input.data;
			const result = await locals.supabase.rpc('submit_publication_release', {
				p_release_class: 'suppression',
				p_items: [
					{
						action: 'suppress_content',
						run: x.run,
						version: x.version,
						field: x.field,
						reason: x.reason,
						expected: x.expected
					}
				] as Json,
				p_reason: x.reason
			});
			if (result.error)
				return fail(result.error.code === '42501' ? 403 : 409, {
					message:
						'Suppression was not submitted. Reload and check the target; it may have changed.'
				});
			return {
				releaseId: result.data,
				message:
					'Suppression release submitted. A different authorised person must approve it before publication.'
			};
		}
		if (intent === 'submit_publication') {
			const input = releaseSubmissionInput.safeParse(Object.fromEntries(form));
			if (!input.success)
				return fail(400, { intent, message: 'Choose a release class and provide a reason.' });
			const result = await locals.supabase.rpc('submit_publication_release', {
				p_release_class: input.data.releaseClass,
				p_items: [{ action: 'publish_change_set', change_set_id: input.data.approval }],
				p_reason: input.data.reason
			});
			if (result.error)
				return fail(result.error.code === '42501' ? 403 : 409, {
					intent,
					message: 'Release was not submitted. Reload the saved approval and try again.'
				});
			return {
				intent,
				releaseId: result.data,
				message:
					input.data.releaseClass === 'initial_seed'
						? 'Initial release submitted for independent approval.'
						: 'Ordinary release submitted under the current portal approval policy.'
			};
		}
		if (intent === 'approve') {
			let fields: unknown;
			try {
				fields = form.getAll('field').map((value) => JSON.parse(String(value)));
			} catch {
				return fail(400, { intent: 'approve', message: 'Invalid field selection.' });
			}
			const parsed = approvalInput.safeParse({ ...Object.fromEntries(form), fields });
			if (!parsed.success)
				return fail(400, {
					intent: 'approve',
					message: 'Select eligible fields and save a matching link/create review first.'
				});
			const x = parsed.data;
			const result = await locals.supabase.rpc('approve_ingestion_fields', {
				p_run: x.run,
				p_version: x.version,
				p_revision: x.revision,
				p_organisation: x.organisation || undefined,
				p_fields: x.fields as Json
			});
			if (result.error)
				return fail(result.error.code === '42501' ? 403 : 409, {
					intent: 'approve',
					sourceBlocked: result.error.message === 'Complete enabled source required',
					message:
						result.error.message === 'Complete enabled source required'
							? 'Approval not saved: the source is paused or the import run is incomplete. A platform administrator can review and enable paused sources on the Source approvals page. Incomplete runs require a new complete import.'
							: result.error.message === 'New organisation requires name'
								? 'Approval not saved: select Entity name when creating a new organisation.'
								: 'Approval not saved. Reload the preview and check the review target, source availability and selected fields.'
				});
			return {
				intent: 'approve',
				approvalId: result.data,
				message: 'Field approval saved. Review the saved values before publishing.'
			};
		}
		if (intent) return fail(400, { message: 'Unknown review action.' });
		const parsed = reviewInput.safeParse(Object.fromEntries(form));
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
