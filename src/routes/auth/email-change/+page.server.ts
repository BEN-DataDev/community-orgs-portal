import { redirect } from '@sveltejs/kit';
import { EMAIL_CHANGE_RESULT } from '$lib/server/email-change';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ url, cookies, locals, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store', 'referrer-policy': 'no-referrer' });
	// Support projects still using Supabase's default ConfirmationURL template.
	// Token-hash templates go through /auth/confirm instead.
	if (url.searchParams.has('error')) {
		cookies.set(EMAIL_CHANGE_RESULT, 'error', {
			path: '/auth/email-change',
			httpOnly: true,
			sameSite: 'lax',
			secure: url.protocol === 'https:',
			maxAge: 300
		});
		redirect(303, '/auth/email-change');
	}
	const code = url.searchParams.get('code');
	if (code && code !== '200') {
		const { data, error } = await locals.supabase.auth.exchangeCodeForSession(code);
		cookies.set(
			EMAIL_CHANGE_RESULT,
			!error && data.user && !data.user.new_email ? 'complete' : 'error',
			{
				path: '/auth/email-change',
				httpOnly: true,
				sameSite: 'lax',
				secure: url.protocol === 'https:',
				maxAge: 300
			}
		);
		redirect(303, '/auth/email-change');
	}
	const result = cookies.get(EMAIL_CHANGE_RESULT);
	cookies.delete(EMAIL_CHANGE_RESULT, { path: '/auth/email-change' });
	// A legacy first-link redirect may contain a message rather than a session.
	// Unverified query text never causes us to claim that the email changed.
	return {
		result:
			result === 'complete' || result === 'pending' || result === 'error' ? result : 'instructions',
		signedIn: !!locals.user && !locals.isAnonymous
	};
};
