import type { PageServerLoad } from './$types';

/**
 * Lists the factors on the account for the initial render.
 *
 * Enrolment and removal happen in the browser — see the note in the page
 * component — but loading the current state here means the page arrives already
 * showing whether MFA is on, rather than flashing "off" until a client fetch
 * lands.
 */
export const load: PageServerLoad = async ({ locals: { supabase, aal } }) => {
	const { data, error } = await supabase.auth.mfa.listFactors();

	if (error) {
		console.error('Could not list MFA factors:', error.message);
		return { factors: [], aal };
	}

	return {
		factors: data.totp.map((factor) => ({
			id: factor.id,
			friendlyName: factor.friendly_name ?? 'Authenticator app',
			status: factor.status,
			createdAt: factor.created_at
		})),
		aal
	};
};
