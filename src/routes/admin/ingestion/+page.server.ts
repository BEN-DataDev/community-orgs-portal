import { z } from 'zod';
import { error, fail } from '@sveltejs/kit';
import {
	isIngestionOperator,
	queueSchema,
	reviewInput,
	fieldPreviewSchema,
	approvalsSchema,
	approvalInput,
	withdrawalSchema,
	suppressionInput
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
	return { queue: parsed.data, offset, search, preview, approvals, withdrawal, withdrawalFields };
};
export const actions: Actions = {
	default: async ({ locals, request }) => {
		if (!(await isIngestionOperator(locals.supabase)))
			error(403, 'Ingestion operator access required.');
		const form = await request.formData();
		const intent = form.get('intent');
		if (intent === 'suppress') {
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
			const result = await locals.supabase.rpc('suppress_ingestion_content', {
				p_run: x.run,
				p_version: x.version,
				p_field: x.field,
				p_reason: x.reason,
				p_expected: x.expected as Json
			});
			if (result.error)
				return fail(result.error.code === '42501' ? 403 : 409, {
					message:
						'Removal was not applied. Reload and check the target; it may have changed or have multiple rows.'
				});
			return {
				message:
					'Suppression saved. The selected content is removed from publication and blocked from restoration.'
			};
		}
		if (intent === 'publish') {
			const id = z.string().uuid().safeParse(form.get('approval'));
			if (!id.success) return fail(400, { message: 'Invalid field approval.' });
			const result = await locals.supabase.rpc('publish_ingestion_fields', {
				p_change_set: id.data
			});
			if (result.error)
				return fail(result.error.code === '42501' ? 403 : 409, {
					message:
						'Publication was not applied. Check source availability, target protection, suppression and review revisions; reload and approve again if needed.'
				});
			return {
				message: 'Approved fields published. Repeating this publication will not apply them twice.'
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
