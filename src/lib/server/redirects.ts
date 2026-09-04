/**
 * Constrains a caller-supplied `redirectTo` to a path inside this application.
 *
 * Only a single leading slash is accepted: `//evil.example` and
 * `https://evil.example` are both protocol-relative or absolute URLs that would
 * send the user off-site, and a backslash is normalised to a slash by some
 * browsers, so those are rejected too.
 */
export function safeRedirect(target: unknown, fallback = '/organisations'): string {
	if (typeof target !== 'string' || target === '') return fallback;
	if (!target.startsWith('/')) return fallback;
	if (target.startsWith('//') || target.startsWith('/\\')) return fallback;
	return target;
}
