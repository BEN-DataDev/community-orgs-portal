import { z } from 'zod';

const id = z.string().regex(/^[1-9][0-9]*$/);

export const campaignDashboardSchema = z.object({
	campaigns: z.array(
		z.object({
			campaign_id: z.string().uuid(),
			campaign_type: z.enum([
				'initial_seed',
				'scheduled_refresh',
				'scope_rebaseline',
				'correction',
				'withdrawal',
				'source_reprocessing'
			]),
			name: z.string(),
			scope_revision_id: id,
			scope_revision: id,
			inclusion_policy_version: z.string(),
			mapping_versions: z.record(z.string()),
			approval_policy_revision: z.number(),
			scheduled_for: z.string().nullable(),
			replaces_campaign_id: z.string().uuid().nullable(),
			reason: z.string(),
			created_at: z.string(),
			created_by: z.string().uuid(),
			readiness: z.object({
				ready: z.boolean(),
				state: z.enum(['blocked', 'ready_for_release', 'release_in_progress', 'published']),
				counts: z.object({
					artifacts: z.number(),
					records: z.number(),
					validation_blockers: z.number(),
					identity_pending: z.number(),
					field_changes_pending: z.number(),
					releases: z.number(),
					published_releases: z.number()
				}),
				blockers: z.array(
					z
						.object({
							code: z.string(),
							stage: z.string(),
							message: z.string(),
							responsible_role: z.string()
						})
						.passthrough()
				)
			}),
			artifacts: z.array(
				z.object({
					artifact_id: z.string().uuid(),
					kind: z.enum(['ingestion_run', 'registry_seed_release']),
					purpose: z.string(),
					source_id: z.string(),
					resource_id: z.string(),
					artifact_key: z.string(),
					parser_version: z.string(),
					observed_at: z.string(),
					required: z.boolean()
				})
			),
			releases: z.array(
				z.object({
					release_id: z.string().uuid(),
					release_class: z.string(),
					status: z.string(),
					revision: z.number(),
					linked_at: z.string()
				})
			)
		})
	)
});
