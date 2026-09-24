import { z } from 'zod';

export const stewardshipState = z.enum([
	'unclaimed',
	'invitation_pending',
	'self_managed',
	'portal_managed',
	'co_managed',
	'suspended'
]);
export const invitationStatus = z.enum(['pending', 'accepted', 'cancelled', 'expired']);

export const stewardshipAdministrationSchema = z.object({
	stewardshipTotal: z.number(),
	stewardshipCounts: z.record(z.number()),
	organisations: z.array(
		z.object({
			organisationId: z.string().uuid(),
			name: z.string(),
			isPublic: z.boolean(),
			state: stewardshipState,
			revision: z.number(),
			updatedAt: z.string(),
			reason: z.string(),
			approvalReference: z.string().nullable(),
			note: z.string(),
			relatedReference: z.string().nullable()
		})
	),
	invitationTotal: z.number(),
	invitations: z.array(
		z.object({
			id: z.string().uuid(),
			organisationId: z.string().uuid(),
			organisationName: z.string(),
			email: z.string(),
			targetStewardship: z.enum(['self_managed', 'co_managed']),
			invitedAt: z.string(),
			expiresAt: z.string(),
			status: invitationStatus,
			closedAt: z.string().nullable(),
			canCancel: z.boolean()
		})
	)
});

export const stewardshipFilters = z.object({
	search: z.string().trim().max(100),
	state: z.union([stewardshipState, z.literal('')]),
	offset: z.coerce.number().int().min(0).max(1_000_000)
});

export const invitationFilters = z.object({
	search: z.string().trim().max(100),
	status: z.union([invitationStatus, z.literal('')]),
	offset: z.coerce.number().int().min(0).max(1_000_000)
});
