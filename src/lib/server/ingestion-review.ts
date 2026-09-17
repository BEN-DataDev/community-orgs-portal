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
	reprocessing: z
		.object({ parent_run_id: id, processed_at: z.string(), quarantined: z.number() })
		.nullable()
		.optional(),
	total: z.number(),
	records: z.array(z.object({ id, native_id: z.string(), name: z.string(), decision: z.string() })),
	detail: z
		.object({
			id,
			native_id: z.string(),
			linked_organisation_id: z.string().uuid().nullable().optional(),
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

export const fieldPreviewSchema = z.object({
	organisation_id: z.string().uuid().nullable(),
	organisation_name: z.string().nullable(),
	fields: z.array(
		z.object({
			field: z.string(),
			section: z.string(),
			label: z.string(),
			atomic_group: z.boolean().nullable(),
			input_value: z.unknown(),
			record_id: z.string(),
			source_token: z.string(),
			mapping_token: z.string(),
			source_version: id,
			mapping_version: z.string().nullable(),
			source_values: z.unknown(),
			table: z.string().nullable(),
			source_value: z.unknown(),
			current_value: z.unknown(),
			status: z.enum([
				'suppressed',
				'unmapped',
				'missing',
				'invalid',
				'ambiguous',
				'unchanged',
				'conflict',
				'new',
				'changed'
			]),
			protected: z.boolean(),
			projection_public: z.boolean().nullable(),
			revision: z.string(),
			target_rows: z.number(),
			changed_at: z.string().nullable()
		})
	)
});

export const approvalsSchema = z.array(
	z.object({
		id: z.string().uuid(),
		review_revision: z.number(),
		organisation_id: z.string().uuid().nullable(),
		fields: z.array(
			z.object({
				field: z.string(),
				current_value: z.unknown(),
				source_value: z.unknown(),
				revision: z.string()
			})
		),
		approved_at: z.string(),
		published_at: z.string().nullable(),
		published_organisation: z.string().uuid().nullable()
	})
);
export const approvalInput = z.object({
	run: id,
	version: id,
	revision: z.coerce.number().int().min(1),
	organisation: z.union([z.string().uuid(), z.literal('')]),
	fields: fieldPreviewSchema.shape.fields.min(1).max(100)
});

export const withdrawalSchema = z.object({
	organisation_id: z.string().uuid().nullable(),
	suppressions: z.array(
		z.object({
			field: z.string().regex(/^(\*|[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)?)$/),
			reason: z.string(),
			suppressed_at: z.string()
		})
	)
});
export const suppressionInput = z.object({
	run: id,
	version: id,
	field: z.string().regex(/^(\*|[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)?)$/),
	reason: z.string().trim().min(1).max(2000),
	expected: z.object({
		organisation_id: z.string().uuid().nullable(),
		field: fieldPreviewSchema.shape.fields.element.optional()
	}),
	confirmed: z.literal('yes')
});
