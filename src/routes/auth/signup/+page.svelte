<script lang="ts">
	import { enhance } from '$app/forms';
	import { page } from '$app/state';
	import EmailRegistrationInput from '$components/ui/auth/EmailRegistrationInput.svelte';
	import OAuthButtons from '$components/ui/auth/OAuthButtons.svelte';
	import TurnstileWidget from '$components/ui/auth/TurnstileWidget.svelte';
	import { captchaRequired } from '$lib/auth/captcha';
	import { createAuthForm } from '$lib/auth/form.svelte';

	let email = $state('');
	let password = $state('');
	let fieldsValid = $state(false);

	const form = createAuthForm();

	const redirectTo = $derived(page.url.searchParams.get('redirectTo') ?? '');

	let captchaToken = $state('');
	const captchaOk = $derived(!captchaRequired() || captchaToken !== '');
</script>

<svelte:head>
	<title>Create an account</title>
</svelte:head>

<div class="card preset-tonal mx-auto my-4 w-full max-w-100 space-y-3 p-5 shadow-md">
	{#if form.errors.general}
		<p class="text-error-500 mb-4">{form.errors.general}</p>
	{/if}

	<form
		id="registrationForm"
		action="?/signup"
		method="post"
		class="space-y-3"
		use:enhance={form.enhance}
	>
		<EmailRegistrationInput
			bind:email
			bind:password
			onValidationChange={(valid) => (fieldsValid = valid)}
			required={true}
		/>

		{#if form.errors.email}
			<p class="text-error-500 text-sm">{form.errors.email}</p>
		{/if}
		{#if form.errors.password}
			<p class="text-error-500 text-sm">{form.errors.password}</p>
		{/if}

		<input type="hidden" name="captchaToken" value={captchaToken} />

		<TurnstileWidget onToken={(received) => (captchaToken = received)} />

		<button
			type="submit"
			class="btn preset-filled-primary-500 min-w-full"
			disabled={!fieldsValid || !captchaOk || form.loading}
		>
			{form.loading ? 'Creating account...' : 'Create account'}
		</button>
	</form>

	<div class="my-4 flex items-center gap-3">
		<hr class="border-surface-300-700 flex-1" />
		<span class="text-surface-600-400 dark:text-surface-700-300 text-sm">or</span>
		<hr class="border-surface-300-700 flex-1" />
	</div>

	<OAuthButtons verb="Sign up" {redirectTo} disabled={form.loading} />
</div>
