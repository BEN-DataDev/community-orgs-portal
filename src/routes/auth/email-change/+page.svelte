<script lang="ts">
	import { resolve } from '$app/paths';
	import type { PageProps } from './$types';
	let { data }: PageProps = $props();
	const copy = $derived(
		data.result === 'complete'
			? {
					title: 'Email address changed',
					body: 'Your new email address is confirmed. Your profile, avatar and organisation access stay with your account.'
				}
			: data.result === 'pending'
				? {
						title: 'One more confirmation',
						body: 'This confirmation was accepted. Open the latest confirmation link in your other inbox to finish changing your email.'
					}
				: data.result === 'error'
					? {
							title: 'Email confirmation failed',
							body: 'This link may have expired or already been used. Check Account Settings for your current email and request another confirmation if the change is still pending.'
						}
					: {
							title: 'Confirm your email change',
							body: 'Follow the confirmation instructions sent to your current and new inboxes. Account Settings shows your current address and any pending change.'
						}
	);
</script>

<svelte:head><title>{copy.title}</title></svelte:head>
<div class="card preset-tonal mx-auto my-4 max-w-xl space-y-4 p-5">
	<h1 class="h3">{copy.title}</h1>
	<p>{copy.body}</p>
	<a class="btn preset-filled-primary-500" href={resolve('/account/settings')}
		>{data.signedIn ? 'Account settings' : 'Sign in to account settings'}</a
	>
</div>
