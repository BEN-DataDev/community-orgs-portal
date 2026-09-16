import { z } from 'zod';
import type { TypedSupabaseClient } from '$lib/supabase-client';

export async function isIngestionOperator(client: TypedSupabaseClient): Promise<boolean> {
	const { data, error } = await client.rpc('is_ingestion_operator');
	return !error && data === true;
}
const id = z.string().regex(/^[1-9][0-9]*$/);
export const reviewInput = z
	.object({
		run: id,
		version: id,
		revision: z.coerce.number().int().min(0).max(2147483646),
		decision: z.enum(['link', 'create', 'defer', 'reject']),
		organisation: z.union([z.string().uuid(), z.literal('')]),
		note: z.string().trim().min(1).max(2000)
	})
	.refine((x) => (x.decision === 'link') === (x.organisation !== ''), {
		message: 'Choose an organisation only for a link decision.'
	});
export const queueSchema = z.object({
	runs: z.array(
		z.object({
			id,
			run_key: z.string(),
			completion: z.string(),
			source_id: z.string(),
			resource_id: z.string(),
			observed_at: z.string()
		})
	),
	run: id.nullable(),
	total: z.number(),
	records: z.array(z.object({ id, native_id: z.string(), name: z.string(), decision: z.string() })),
	detail: z
		.object({
			id,
			native_id: z.string(),
			payload: z
				.object({ assertions: z.array(z.object({ field: z.string(), value: z.unknown() })) })
				.passthrough(),
			review: z
				.object({
					revision: z.number(),
					decision: z.string(),
					organisation_id: z.string().nullable(),
					note: z.string(),
					reviewed_at: z.string()
				})
				.nullable()
		})
		.nullable(),
	candidates: z.array(
		z.object({
			org_id: z.string().uuid(),
			entity_name: z.string(),
			abn: z.string().nullable(),
			website: z.string().nullable(),
			physical_address: z.string().nullable(),
			postal_address: z.string().nullable(),
			reason: z.string()
		})
	)
});
