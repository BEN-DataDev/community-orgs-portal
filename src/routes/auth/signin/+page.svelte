<script lang="ts">
	import { enhance } from '$app/forms';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import EmailSignInInput from '$components/ui/auth/EmailSignInInput.svelte';
	import OAuthButtons from '$components/ui/auth/OAuthButtons.svelte';
	import TurnstileWidget from '$components/ui/auth/TurnstileWidget.svelte';
	import { captchaRequired } from '$lib/auth/captcha';
	import { createAuthForm } from '$lib/auth/form.svelte';
	import { isValidEmail } from '$lib/auth/schemas';

	let email = $state('');
	let password = $state('');
	let fieldsValid = $state(false);

	const form = createAuthForm();

	const redirectTo = $derived(page.url.searchParams.get('redirectTo') ?? '');

	/**
	 * The magic-link button submits the same form to a different action, so it
	 * only needs the email field — the password box is irrelevant to it.
	 */
	const emailValid = $derived(isValidEmail(email));

	/**
	 * Supabase applies its CAPTCHA setting to every auth endpoint, not just the
	 * anonymous one, so both buttons below need a token before they can submit.
	 */
	let captchaToken = $state('');
	const captchaOk = $derived(!captchaRequired() || captchaToken !== '');
</script>

<div class="card preset-tonal mx-auto my-4 w-full max-w-100 space-y-3 p-5 shadow-md">
	{#if form.errors.general}
		<p class="text-error-500 mb-4">{form.errors.general}</p>
	{/if}

	<form
		id="signInForm"
		action="?/signin"
		method="post"
		class="space-y-3"
		use:enhance={form.enhance}
	>
		<EmailSignInInput
			bind:email
			bind:password
			onValidationChange={(valid) => (fieldsValid = valid)}
			required={true}
		/>
		<input type="hidden" name="redirectTo" value={redirectTo} />
		<input type="hidden" name="captchaToken" value={captchaToken} />

		{#if form.errors.email}
			<p class="text-error-500 text-sm">{form.errors.email}</p>
		{/if}
		{#if form.errors.password}
			<p class="text-error-500 text-sm">{form.errors.password}</p>
		{/if}

		<TurnstileWidget onToken={(received) => (captchaToken = received)} />

		<button
			type="submit"
			class="btn preset-filled-primary-500 min-w-full"
			disabled={!fieldsValid || !captchaOk || form.loading}
		>
			{form.loading ? 'Signing in...' : 'Sign In'}
		</button>

		<!--
			Same form, different action. `formaction` lets the magic-link path
			reuse the email field already filled in above rather than asking for
			it a second time in a form of its own.
		-->
		<button
			type="submit"
			formaction="?/magiclink"
			class="btn preset-tonal min-w-full"
			disabled={!emailValid || !captchaOk || form.loading}
		>
			Email me a sign-in link
		</button>
		<p class="text-surface-600-400 text-center text-xs">
			No password needed — we send a one-time link to your inbox.
		</p>
	</form>

	<div class="my-4 flex items-center gap-3">
		<hr class="border-surface-300-700 flex-1" />
		<span class="text-surface-600-400 dark:text-surface-700-300 text-sm">or</span>
		<hr class="border-surface-300-700 flex-1" />
	</div>

	<OAuthButtons verb="Sign in" {redirectTo} disabled={form.loading} />

	<div class="mt-6 flex flex-wrap items-center justify-center gap-2">
		<span class="text-surface-700-300">Not registered?</span>
		<a href={resolve('/auth/signup')} class="btn btn-sm preset-tonal">Create an Account</a>
	</div>
</div>
