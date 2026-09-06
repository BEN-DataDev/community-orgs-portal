<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';

	/**
	 * Three different flows land here — signup, magic link and password recovery
	 * — and each sends a different email. The page used to say "confirm your
	 * account" regardless, which is wrong for the other two.
	 *
	 * The copy is deliberately identical in structure across all three and never
	 * says whether an account exists: `/auth/forgot-password` and the magic-link
	 * action both redirect here unconditionally so that this page cannot be used
	 * to test whether an address is registered.
	 */
	const copy = {
		signup: {
			title: 'Confirm your email',
			body: 'We have sent you a confirmation link. Open it to finish setting up your account.'
		},
		magiclink: {
			title: 'Check your email',
			body: 'If that address has an account, we have sent it a sign-in link. Open it on this device to sign in.'
		},
		recovery: {
			title: 'Check your email',
			body: 'If that address has an account, we have sent it a link to set a new password.'
		}
	} as const;

	type Reason = keyof typeof copy;

	const reason = $derived(
		((page.url.searchParams.get('reason') ?? 'signup') as Reason) in copy
			? ((page.url.searchParams.get('reason') ?? 'signup') as Reason)
			: 'signup'
	);
	const { title, body } = $derived(copy[reason]);
</script>

<svelte:head>
	<title>{title}</title>
</svelte:head>

<div class="card preset-tonal mx-auto my-4 w-full max-w-100 space-y-3 p-5 shadow-md">
	<h1 class="text-xl font-bold">{title}</h1>
	<p>{body}</p>
	<p class="text-surface-700-300 text-sm">
		Links expire after 30 minutes. If nothing arrives, check your spam folder before requesting
		another.
	</p>
	<a class="btn preset-filled-primary-500" href={resolve('/auth/signin')}>Back to sign in</a>
</div>
