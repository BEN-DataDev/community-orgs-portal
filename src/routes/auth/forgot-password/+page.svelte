<script lang="ts">
	import { enhance } from '$app/forms';
	import { resolve } from '$app/paths';
	import TurnstileWidget from '$components/ui/auth/TurnstileWidget.svelte';
	import { captchaRequired } from '$lib/auth/captcha';
	import { createAuthForm } from '$lib/auth/form.svelte';
	import { isValidEmail } from '$lib/auth/schemas';

	let email = $state('');
	const form = createAuthForm();

	const emailValid = $derived(isValidEmail(email));

	let captchaToken = $state('');
	const captchaOk = $derived(!captchaRequired() || captchaToken !== '');
</script>

<svelte:head>
	<title>Reset your password</title>
</svelte:head>

<div class="card preset-tonal mx-auto my-4 w-full max-w-100 space-y-3 p-5 shadow-md">
	<h1 class="h3">Reset your password</h1>
	<p class="text-surface-700-300 text-sm">
		Enter the email address you signed up with and we will send you a link to set a new password.
	</p>

	{#if form.errors.general}
		<p class="text-error-500">{form.errors.general}</p>
	{/if}

	<form action="?/request" method="post" class="space-y-3" use:enhance={form.enhance}>
		<input
			type="email"
			class="input"
			name="email"
			placeholder="Email"
			autocomplete="email"
			required
			bind:value={email}
		/>

		{#if email && !emailValid}
			<p class="text-error-500 text-sm">Please enter a valid email address</p>
		{/if}
		{#if form.errors.email}
			<p class="text-error-500 text-sm">{form.errors.email}</p>
		{/if}

		<input type="hidden" name="captchaToken" value={captchaToken} />

		<TurnstileWidget onToken={(received) => (captchaToken = received)} />

		<button
			type="submit"
			class="btn preset-filled-primary-500 min-w-full"
			disabled={!emailValid || !captchaOk || form.loading}
		>
			{form.loading ? 'Sending...' : 'Send reset link'}
		</button>
	</form>

	<div class="mt-6 flex flex-wrap items-center justify-center gap-2">
		<span class="text-surface-700-300">Remembered it?</span>
		<a href={resolve('/auth/signin')} class="btn btn-sm preset-tonal">Back to sign in</a>
	</div>
</div>
