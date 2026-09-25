import { error, fail } from '@sveltejs/kit';
import { z } from 'zod';
import { emailSchema } from '$lib/auth/schemas';
import type { Actions, PageServerLoad, RequestEvent } from './$types';

const rosterSchema = z.object({
	name: z.string(),
	level: z.number(),
	canInvite: z.boolean(),
	roles: z.array(z.object({ id: z.string().uuid(), name: z.string(), level: z.number() })),
	assignments: z.array(
		z.object({
			id: z.string().uuid(),
			userId: z.string().uuid(),
			roleId: z.string().uuid(),
			role: z.string(),
			level: z.number(),
			active: z.boolean(),
			expiresAt: z.string().nullable(),
			grantedAt: z.string().nullable(),
			status: z.enum(['Active', 'Expired', 'Revoked']),
			canRevoke: z.boolean()
		})
	),
	invitations: z.array(
		z.object({
			id: z.string().uuid(),
			email: z.string(),
			targetStewardship: z.enum(['self_managed', 'co_managed']),
			invitedAt: z.string(),
			expiresAt: z.string(),
			status: z.enum(['pending', 'accepted', 'cancelled', 'expired']),
			canCancel: z.boolean()
		})
	)
});
async function requireManager({ locals, params }: RequestEvent) {
	if (!locals.user || locals.isAnonymous)
		error(403, 'A registered account with organisation management access is required.');
	if (!z.string().uuid().safeParse(params.id).success) error(404, 'Organisation not found.');
	const result = await locals.providers.database.rpc('organisation_role_assignments', {
		p_organisation_id: params.id
	});
	if (result.error) {
		if (result.error.code === '42501')
			error(403, 'Organisation management access and any enrolled MFA verification are required.');
		error(500, 'Could not load role assignments.');
	}
	const parsed = rosterSchema.safeParse(result.data);
	if (!parsed.success) error(500, 'Could not load role assignments.');
	return parsed.data;
}
export const load: PageServerLoad = async (event) => {
	event.setHeaders({ 'cache-control': 'private, no-store' });
	return { roster: await requireManager(event), actorId: event.locals.user!.id };
};
const refusalMessages: Record<string, string> = {
	'target must be a registered account': 'That account ID does not belong to a registered account.',
	'cannot change assignments for someone ranked above you':
		'You cannot change assignments for someone ranked above you.',
	'cannot revoke a role from someone ranked above you':
		'You cannot revoke roles from someone ranked above you.',
	'cannot grant a role above your own': 'You cannot grant a role above your own.',
	'cannot revoke a role above your own': 'You cannot revoke a role above your own.',
	'you cannot revoke your own assignments':
		'Ask another authorised manager to revoke your assignment.',
	'grant another non-expiring owner before revoking this owner':
		'Grant another account a non-expiring owner role before revoking this owner.'
};
const fields = z.object({ userId: z.string().uuid(), roleId: z.string().uuid() });
async function change(event: RequestEvent, revoke: boolean) {
	await requireManager(event);
	const form = Object.fromEntries(await event.request.formData());
	const parsed = fields.safeParse(form);
	if (!parsed.success)
		return fail(400, { success: false, message: 'Enter a valid account ID and select a role.' });
	if (revoke && form.confirm !== 'yes')
		return fail(400, { success: false, message: 'Confirm the revocation before submitting.' });
	if (typeof form.reason === 'string' && form.reason.length > 1000)
		return fail(400, { success: false, message: 'Keep the reason under 1,000 characters.' });
	const args = {
		p_user_id: parsed.data.userId,
		p_role_id: parsed.data.roleId,
		p_organisation_id: event.params.id
	};
	const result = revoke
		? await event.locals.providers.database.rpc('revoke_user_role', {
				...args,
				p_revoked_by: event.locals.user!.id,
				p_reason: typeof form.reason === 'string' ? form.reason.trim() : ''
			})
		: await event.locals.providers.database.rpc('grant_user_role', {
				...args,
				p_granted_by: event.locals.user!.id
			});
	if (result.error)
		return fail(result.error.code === '42501' ? 403 : 400, {
			success: false,
			message:
				refusalMessages[result.error.message] ??
				'The change was refused. Check the account ID, current role hierarchy and owner safeguards, then reload and retry.'
		});
	if (!result.data)
		return fail(409, {
			success: false,
			message: 'This assignment is no longer active. Reload to see the current assignments.'
		});
	return { success: true, message: revoke ? 'Role revoked.' : 'Role granted without expiry.' };
}
export const actions: Actions = {
	grant: (event) => change(event, false),
	revoke: (event) => change(event, true),
	invite: async (event) => {
		const roster = await requireManager(event);
		if (!roster.canInvite)
			return fail(403, {
				success: false,
				message: 'Only a Portal Administrator can invite an owner for an unclaimed organisation.'
			});
		const form = Object.fromEntries(await event.request.formData());
		const parsed = z
			.object({
				email: emailSchema,
				targetStewardship: z.enum(['self_managed', 'co_managed']),
				reason: z.string().trim().min(1).max(2000),
				approvalReference: z.string().trim().min(1).max(500),
				note: z.string().trim().min(1).max(4000),
				expiresInDays: z.coerce.number().int().min(1).max(30)
			})
			.safeParse(form);
		if (!parsed.success)
			return fail(400, {
				success: false,
				message: 'Enter a valid email, outcome, expiry, reason, approval reference and note.'
			});
		const expiresAt = new Date(
			Date.now() + parsed.data.expiresInDays * 24 * 60 * 60 * 1000
		).toISOString();
		const result = await event.locals.providers.database.rpc('issue_organisation_invitation', {
			p_organisation_id: event.params.id,
			p_email: parsed.data.email,
			p_target_stewardship: parsed.data.targetStewardship,
			p_reason: parsed.data.reason,
			p_approval_reference: parsed.data.approvalReference,
			p_note: parsed.data.note,
			p_expires_at: expiresAt
		});
		if (result.error)
			return fail(result.error.code === '42501' ? 403 : 400, {
				success: false,
				message:
					result.error.message === 'This organisation already has a pending invitation'
						? 'This organisation already has a pending invitation.'
						: 'The invitation could not be issued. Reload and check the stewardship state.'
			});
		return {
			success: true,
			message: 'Invitation issued. Send the acceptance link to the named email address.',
			invitationUrl: `/invitations/${result.data}`
		};
	},
	cancelInvitation: async (event) => {
		await requireManager(event);
		const form = Object.fromEntries(await event.request.formData());
		const parsed = z
			.object({ invitationId: z.string().uuid(), reason: z.string().trim().min(1).max(2000) })
			.safeParse(form);
		if (!parsed.success)
			return fail(400, { success: false, message: 'A valid invitation and reason are required.' });
		const result = await event.locals.providers.database.rpc('cancel_organisation_invitation', {
			p_invitation_id: parsed.data.invitationId,
			p_reason: parsed.data.reason
		});
		if (result.error)
			return fail(result.error.code === '42501' ? 403 : 400, {
				success: false,
				message: 'The invitation could not be cancelled.'
			});
		if (!result.data)
			return fail(409, { success: false, message: 'That invitation is already closed.' });
		return { success: true, message: 'Invitation closed without granting access.' };
	}
};
