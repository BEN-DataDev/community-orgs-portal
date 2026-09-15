import type { EmailOtpType } from '@supabase/supabase-js';
import { redirect } from '@sveltejs/kit';
import { safeRedirect } from '$lib/server/redirects';
import { EMAIL_CHANGE_RESULT } from '$lib/server/email-change';
import type { RequestHandler } from './$types';

const types = new Set(['signup', 'invite', 'magiclink', 'recovery', 'email_change', 'email']);

export const GET: RequestHandler = async ({ url, cookies, locals: { supabase } }) => {
	const token_hash = url.searchParams.get('token_hash');
	const type = url.searchParams.get('type');
	const next = safeRedirect(url.searchParams.get('next'), '/');
	let result = 'error';
	if (token_hash && type && types.has(type)) {
		const { data, error } = await supabase.auth.verifyOtp({
			type: type as EmailOtpType,
			token_hash
		});
		if (!error) {
			if (type !== 'email_change') redirect(303, new URL(next, url.origin));
			// Secure email change's FIRST confirmation returns no session/user.
			// Do not mistake that successful verification for a completed change.
			result = data.session && data.user && !data.user.new_email ? 'complete' : 'pending';
		}
	}
	if (type === 'email_change') {
		cookies.set(EMAIL_CHANGE_RESULT, result, {
			path: '/auth/email-change',
			httpOnly: true,
			sameSite: 'lax',
			secure: url.protocol === 'https:',
			maxAge: 300
		});
		redirect(303, '/auth/email-change');
	}
	// Construct a clean destination: never carry token hashes into another page.
	redirect(303, '/auth/error?reason=expired');
};
