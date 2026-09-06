import { z } from 'zod';

/**
 * The single source of truth for auth field validation, shared by the server
 * actions under `src/routes/auth` and the input components under
 * `src/components/ui/auth`.
 *
 * These previously disagreed: the sign-in component accepted any password of
 * six characters or more while the sign-up action demanded eight, so a password
 * the form called valid was rejected on submit. Importing the same schema on
 * both sides is what stops that drifting again.
 *
 * `PASSWORD_MIN_LENGTH` and the character-class rule below must stay in step
 * with `[auth] minimum_password_length` and `password_requirements` in
 * `supabase/config.toml`. GoTrue enforces those independently, and a mismatch
 * shows up as an opaque "Password is too weak" from the Auth API rather than a
 * field-level message.
 */
export const PASSWORD_MIN_LENGTH = 8;

export const emailSchema = z.string().trim().email('Enter a valid email address');

/**
 * Matches `password_requirements = "lower_upper_letters_digits"`.
 */
export const passwordSchema = z
	.string()
	.min(PASSWORD_MIN_LENGTH, `Use at least ${PASSWORD_MIN_LENGTH} characters`)
	.regex(/[a-z]/, 'Include a lowercase letter')
	.regex(/[A-Z]/, 'Include an uppercase letter')
	.regex(/[0-9]/, 'Include a number');

/**
 * Sign-in deliberately does *not* use `passwordSchema`. An existing account may
 * predate the current rules, and telling someone their password "needs an
 * uppercase letter" at the sign-in prompt leaks the policy without helping them
 * in. Any non-empty value is passed through to Supabase to accept or reject.
 */
export const signInSchema = z.object({
	email: emailSchema,
	password: z.string().min(1, 'Enter your password')
});

export const signUpSchema = z.object({
	email: emailSchema,
	password: passwordSchema
});

export const magicLinkSchema = z.object({
	email: emailSchema
});

export const resetRequestSchema = z.object({
	email: emailSchema
});

export const newPasswordSchema = z.object({
	password: passwordSchema
});

/** TOTP codes from an authenticator app are always six digits. */
export const totpCodeSchema = z.object({
	code: z
		.string()
		.trim()
		.regex(/^\d{6}$/, 'Enter the 6-digit code from your authenticator app')
});

/**
 * Client-side helpers. The components need a boolean per field to drive the
 * submit button and inline messages, not a parsed object, so they check against
 * the same schemas rather than re-implementing the rules with their own regexes.
 */
export function isValidEmail(email: string): boolean {
	return emailSchema.safeParse(email).success;
}

export function passwordProblems(password: string): string[] {
	const parsed = passwordSchema.safeParse(password);
	return parsed.success ? [] : parsed.error.issues.map((issue) => issue.message);
}
