<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import AuthErrorCard from '$components/ui/auth/AuthErrorCard.svelte';

	/**
	 * This is a normal page reached by redirect, not an error boundary, so
	 * `page.status` is 200 and `page.error` is null — the previous version of
	 * this file rendered a literal "200 / Something went wrong." The `reason`
	 * parameter set by `/auth/callback` and `/auth/confirm` is what actually
	 * carries the information.
	 *
	 * The messages stay vague about *which* account or link failed: this page is
	 * reachable by anyone with a crafted URL.
	 */
	const messages: Record<string, string> = {
		expired: 'That link has expired or has already been used. Request a new one and try again.',
		declined: 'The sign-in was cancelled before it completed.',
		exchange: 'We could not complete that sign-in. This usually means the link was already used.'
	};

	const reason = $derived(page.url.searchParams.get('reason') ?? '');
	const message = $derived(
		messages[reason] ?? 'We could not complete that sign-in. Please try again.'
	);
</script>

<AuthErrorCard
	title="Sign-in did not complete"
	{message}
	actionLabel="Back to sign in"
	actionHref={resolve('/auth/signin')}
/>
