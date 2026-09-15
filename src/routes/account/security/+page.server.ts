import { fail, redirect } from '@sveltejs/kit';
import { z } from 'zod';
import { needsMfaChallenge } from '$lib/auth/session';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals: { supabase, aal }, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	const [factors, sessions] = await Promise.all([
		supabase.auth.mfa.listFactors(),
		supabase.rpc('get_account_sessions')
	]);
	return {
		factors: factors.error
			? []
			: factors.data.totp.map((factor) => ({
					id: factor.id,
					friendlyName: factor.friendly_name ?? 'Authenticator app',
					status: factor.status,
					createdAt: factor.created_at
				})),
		factorsUnavailable: !!factors.error,
		accountSessions: sessions.error ? null : sessions.data,
		aal
	};
};

export const actions: Actions = {
	default: async ({ request, locals }) => {
		if (!locals.user || locals.isAnonymous || !locals.session)
			return fail(403, { sessionError: 'Sign in with an account to manage sessions.' });
		if (!locals.aal || needsMfaChallenge(locals.aal))
			return fail(403, { sessionError: 'Complete verification before managing sessions.' });
		const fields = await request.formData();
		const intent = fields.get('intent');
		if (intent === 'revokeSession') {
			const parsed = z.string().uuid().safeParse(fields.get('sessionId'));
			if (!parsed.success) return fail(400, { sessionError: 'Choose a valid session.' });
			const { data, error } = await locals.supabase.rpc('revoke_account_session', {
				p_session_id: parsed.data
			});
			if (error)
				return fail(400, {
					sessionError: 'Could not sign out that session. Refresh the list and try again.'
				});
			return {
				sessionMessage: data ? 'Session signed out.' : 'That session is no longer available.'
			};
		}
		if (intent !== 'signOutOthers' && intent !== 'signOutAll')
			return fail(400, { sessionError: 'Choose a valid session action.' });
		// Recheck the live session and enrolled MFA in the database, not only the
		// potentially older claims in the token, before the bulk Auth operation.
		const { error: accessError } = await locals.supabase.rpc('get_account_sessions');
		if (accessError)
			return fail(403, {
				sessionError: 'Refresh the page and verify your session before trying again.'
			});
		const { error } = await locals.supabase.auth.signOut({
			scope: intent === 'signOutOthers' ? 'others' : 'global'
		});
		if (error)
			return fail(400, { sessionError: 'Could not sign out the sessions. Please try again.' });
		if (intent === 'signOutAll') redirect(303, '/auth/signin');
		return { sessionMessage: 'Other sessions signed out. This session remains signed in.' };
	}
};
