import { error } from '@sveltejs/kit';
import { z } from 'zod';
import type { DomainDatabase } from '$lib/server/providers/contracts';
import {
	approvalsSchema,
	fieldPreviewSchema,
	queueSchema,
	withdrawalSchema
} from '$lib/server/ingestion-review';

const recordId = /^[1-9][0-9]{0,18}$/;

export function reviewQueueParams(url: URL) {
	const run = url.searchParams.get('run') || undefined;
	const version = url.searchParams.get('version') || undefined;
	const offset = Number(url.searchParams.get('offset') || 0);
	const search = url.searchParams.get('search') || '';
	const campaign = url.searchParams.get('campaign') || '';
	if (
		[run, version].some((value) => value && !recordId.test(value)) ||
		!Number.isInteger(offset) ||
		offset < 0 ||
		offset > 1_000_000 ||
		search.length > 100 ||
		(campaign && !z.string().uuid().safeParse(campaign).success)
	)
		error(400, 'Invalid review filter.');
	return { run, version, offset, search, campaign };
}

export async function loadReviewQueue(client: DomainDatabase, url: URL) {
	const params = reviewQueueParams(url);
	const result = await client.rpc('ingestion_review_queue', {
		p_run: params.run,
		p_version: params.version,
		p_offset: params.offset,
		p_search: params.search
	});
	if (result.error)
		error(
			result.error.code === 'P0002' ? 404 : result.error.code === '42501' ? 403 : 500,
			'Could not load the review queue.'
		);
	const parsed = queueSchema.safeParse(result.data);
	if (!parsed.success) error(500, 'Unexpected review queue response.');
	return { queue: parsed.data, ...params };
}

export async function loadFieldContext(
	client: DomainDatabase,
	url: URL,
	loaded: Awaited<ReturnType<typeof loadReviewQueue>>
) {
	const { queue } = loaded;
	if (!queue.detail || !queue.run) return { preview: null, approvals: [] };
	const target =
		url.searchParams.get('target') ??
		queue.detail.review?.organisation_id ??
		queue.detail.identity_match?.organisation_id ??
		queue.detail.linked_organisation_id ??
		'';
	if (target && !z.string().uuid().safeParse(target).success)
		error(400, 'Invalid preview organisation.');
	const [previewResult, approvalResult] = await Promise.all([
		client.rpc('ingestion_field_preview', {
			p_run: queue.run,
			p_version: queue.detail.id,
			p_organisation: target || undefined
		}),
		client.rpc('ingestion_field_approvals', { p_version: queue.detail.id })
	]);
	const preview = fieldPreviewSchema.safeParse(previewResult.data);
	const approvals = approvalsSchema.safeParse(approvalResult.data);
	if (previewResult.error || !preview.success)
		error(previewResult.error?.code === '42501' ? 403 : 500, 'Could not load field preview.');
	if (approvalResult.error || !approvals.success) error(500, 'Could not load field approvals.');
	return { preview: preview.data, approvals: approvals.data };
}

export async function loadSuppressionContext(
	client: DomainDatabase,
	url: URL,
	loaded: Awaited<ReturnType<typeof loadReviewQueue>>
) {
	const fields = await loadFieldContext(client, url, loaded);
	if (!loaded.queue.detail) return { withdrawal: null, withdrawalFields: [], ...fields };
	const status = await client.rpc('ingestion_withdrawal_status', {
		p_version: loaded.queue.detail.id
	});
	const withdrawal = withdrawalSchema.safeParse(status.data);
	if (status.error || !withdrawal.success)
		error(status.error?.code === '42501' ? 403 : 500, 'Could not load withdrawal status.');
	let withdrawalFields = fields.preview?.fields ?? [];
	if (
		withdrawal.data.organisation_id &&
		fields.preview?.organisation_id !== withdrawal.data.organisation_id &&
		loaded.queue.run
	) {
		const target = await client.rpc('ingestion_field_preview', {
			p_run: loaded.queue.run,
			p_version: loaded.queue.detail.id,
			p_organisation: withdrawal.data.organisation_id
		});
		const parsed = fieldPreviewSchema.safeParse(target.data);
		if (target.error || !parsed.success) error(500, 'Could not load withdrawal target.');
		withdrawalFields = parsed.data.fields;
	}
	return { withdrawal: withdrawal.data, withdrawalFields, ...fields };
}
