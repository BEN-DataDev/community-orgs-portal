import { fail, type ActionFailure } from '@sveltejs/kit';
import { emailSchema } from '$lib/auth/schemas';

interface EmailChangeResult {
	emailError?: string;
	emailMessage?: string;
	emailValue?: string;
}

export async function requestEmailChange(
	locals: App.Locals,
	fields: FormData,
	origin: string,
	resend: boolean
): Promise<EmailChangeResult | ActionFailure<EmailChangeResult>> {
	const user = locals.user!; // The Settings action checks permanent account and MFA first.
	const emailRedirectTo = `${origin}/auth/email-change`;
	const failure = (error: { status?: number; code?: string }) =>
		fail(error.status === 429 ? 429 : 400, {
			emailError:
				error.status === 429 || error.code === 'over_email_send_rate_limit'
					? 'Too many requests. Wait a minute before trying again.'
					: 'Could not request this email change. Check the address and try again.'
		});
	try {
		if (resend) {
			if (!user.new_email || !user.email)
				return fail(400, { emailError: 'There is no pending email change. Reload your settings.' });
			// Supabase looks up the account by its CURRENT address, not new_email.
			const { error } = await locals.supabase.auth.resend({
				type: 'email_change',
				email: user.email,
				options: { emailRedirectTo }
			});
			if (error) return failure(error);
			return {
				emailMessage:
					'Confirmation requested again. Check your current and new inboxes and follow the latest links.'
			};
		}
		const parsed = emailSchema.max(254).safeParse(fields.get('email'));
		if (!parsed.success) return fail(400, { emailError: 'Enter a valid new email address.' });
		const email = parsed.data.toLowerCase();
		if (email === user.email?.toLowerCase())
			return fail(400, { emailError: 'Enter an address different from your current email.' });
		const confirmation = fields.get('emailConfirmation');
		if (typeof confirmation !== 'string' || confirmation.trim().toLowerCase() !== email)
			return fail(400, { emailError: 'The email addresses do not match.', emailValue: email });
		if (email === user.new_email?.toLowerCase())
			return fail(400, {
				emailError: 'This change is already pending. Use Resend confirmation instead.'
			});
		const { data, error } = await locals.supabase.auth.updateUser({ email }, { emailRedirectTo });
		if (error) return failure(error);
		if (data.user) locals.user = data.user;
		return {
			emailMessage:
				'Email change requested. Check your current and new inboxes and follow the confirmation instructions.'
		};
	} catch {
		return fail(503, { emailError: 'The email service is unavailable. Please try again shortly.' });
	}
}

export const EMAIL_CHANGE_RESULT = 'email_change_result';
