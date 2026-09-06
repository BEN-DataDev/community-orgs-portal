import { env } from '$env/dynamic/public';

/**
 * Whether the auth forms must carry a Turnstile token.
 *
 * Supabase's CAPTCHA setting is project-wide, so this is all-or-nothing: with it
 * on, every sign-up, sign-in, magic-link and password-reset request needs a
 * token or the Auth server returns `captcha_failed`. Keyed off the public site
 * key so an environment without one — a preview build, a fresh checkout — still
 * has working auth forms rather than permanently disabled buttons.
 *
 * That does mean the two halves must be configured together: setting
 * `[auth.captcha] enabled` without `PUBLIC_TURNSTILE_SITE_KEY` locks everyone
 * out of signing in.
 */
export function captchaRequired(): boolean {
	return !!env.PUBLIC_TURNSTILE_SITE_KEY;
}

/**
 * The token to hand to `supabase.auth.*` — `undefined` rather than an empty
 * string when captcha is off, since the client library forwards the key either
 * way and the Auth server rejects an empty one.
 */
export function captchaOption(token: FormDataEntryValue | null): string | undefined {
	return typeof token === 'string' && token !== '' ? token : undefined;
}
