import type { Provider } from '@supabase/supabase-js';

/**
 * The OAuth providers this application offers.
 *
 * This is an allow-list, not a convenience: `/auth/oauth/[provider]` takes the
 * provider name straight out of the URL, and Supabase supports twenty-odd of
 * them. Without a check here, anyone could drive the app into starting a flow
 * with a provider the project never configured — at best a confusing error, at
 * worst a hand-off to somewhere unintended.
 *
 * `slug` is what appears in the URL and is passed to `signInWithOAuth`.
 * Microsoft is `azure` to Supabase, which is why the label and the slug differ.
 */
export interface OAuthProvider {
	slug: Provider;
	label: string;
}

export const OAUTH_PROVIDERS = [
	{ slug: 'github', label: 'GitHub' },
	{ slug: 'google', label: 'Google' },
	{ slug: 'azure', label: 'Microsoft' },
	{ slug: 'discord', label: 'Discord' }
] as const satisfies readonly OAuthProvider[];

export type OAuthProviderSlug = (typeof OAUTH_PROVIDERS)[number]['slug'];

export function isOAuthProvider(value: string): value is OAuthProviderSlug {
	return OAUTH_PROVIDERS.some((provider) => provider.slug === value);
}

export function oauthProviderLabel(slug: OAuthProviderSlug): string {
	return OAUTH_PROVIDERS.find((provider) => provider.slug === slug)?.label ?? slug;
}

/**
 * Scopes Supabase does not request by default.
 *
 * Azure needs `email` spelled out or the token comes back without one, and a
 * user with no email address cannot be matched to an invitation or an
 * organisation membership. The others are fine on their defaults.
 */
export const PROVIDER_SCOPES: Partial<Record<OAuthProviderSlug, string>> = {
	azure: 'openid email profile'
};
