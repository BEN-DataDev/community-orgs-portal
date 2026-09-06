<script lang="ts">
	import { enhance } from '$app/forms';
	import { Github } from 'lucide-svelte';
	import { page } from '$app/state';
	import EmailRegistrationInput from '$components/ui/auth/EmailRegistrationInput.svelte';
	import type { ActionData } from './$types';
	import type { SubmitFunction } from '@sveltejs/kit';

	interface FormData {
		email: string;
		password: string;
		provider?: 'email' | 'github' | 'discord';
		errors: {
			email?: string;
			password?: string;
			general?: string;
		};
	}

	interface FormErrors {
		email?: string;
		password?: string;
		general?: string;
		[key: string]: string | undefined;
	}

	let { form }: { form: ActionData | null } = $props();

	const formDefault: FormData = {
		email: '',
		password: '',
		provider: 'email',
		errors: {}
	};

	let formData = $state<FormData>(formDefault);
	let loading = $state(false);

	$effect(() => {
		if (form) {
			const actionData = form as unknown as {
				errors?: FormErrors;
				data?: Partial<FormData>;
				error?: string;
			};

			if (actionData.errors) {
				formData = {
					...formDefault,
					errors: actionData.errors
				};
			} else if (actionData.data) {
				formData = {
					...formDefault,
					...actionData.data,
					errors: {}
				};
			} else if (actionData.error) {
				formData = {
					...formDefault,
					errors: { general: actionData.error }
				};
			}
		}
	});

	let emailPasswordValid = $state(false);

	function handleValidationChange(validated: boolean) {
		emailPasswordValid = validated;
	}

	type FormErrorKey = keyof FormErrors;
	let formErrors = $state<Partial<Record<FormErrorKey, string>>>({});

	const handleEnhance: SubmitFunction = () => {
		return async ({ result }) => {
			loading = true;
			formErrors = {};
			try {
				if (result.type === 'error') {
					formErrors = { general: 'A network error occurred. Please try again.' };
				} else if (result.type === 'failure') {
					const failureData = result.data as { errors?: FormErrors; error?: string };
					formErrors = failureData.errors || { general: failureData.error || 'Submission failed' };
				} else if (result.type === 'success') {
					return;
				}
			} catch (error) {
				console.error('Error during form submission:', error);
				formErrors = { general: 'An unexpected error occurred. Please try again.' };
			} finally {
				loading = false;
			}
		};
	};

	const submissionValid = $derived(emailPasswordValid || formData.provider !== 'email');
</script>

<svelte:head>
	<title>Registration Form</title>
</svelte:head>

<div class="card preset-tonal mx-auto my-4 w-full max-w-100 space-y-3 p-5 shadow-md">
	{#if formErrors.general}
		<p class="text-error-500 mb-4">{formErrors.general}</p>
	{/if}
	<form
		id="registrationForm"
		action="?/signup"
		method="post"
		class="space-y-3"
		enctype="multipart/form-data"
		use:enhance={handleEnhance}
	>
		<EmailRegistrationInput
			email={formData.email}
			password={formData.password}
			onValidationChange={handleValidationChange}
			onPasswordChange={(newPassword) => (formData.password = newPassword)}
			required={true}
		/>
		<input type="hidden" name="password" bind:value={formData.password} />
		{#if formErrors.email}
			<p class="text-error-500 text-sm">{formErrors.email}</p>
		{/if}
		{#if formErrors.password}
			<p class="text-error-500 text-sm">{formErrors.password}</p>
		{/if}
		<input type="hidden" name="provider" bind:value={formData.provider} />
		<button
			type="submit"
			class="btn preset-filled-primary-500 min-w-full"
			disabled={!submissionValid || loading}
		>
			{loading ? 'Submitting...' : 'Submit'}
		</button>
	</form>

	<div class="my-4 flex items-center gap-3">
		<hr class="border-surface-300-700 flex-1" />
		<span class="text-surface-600-400 dark:text-surface-700-300 text-sm">or</span>
		<hr class="border-surface-300-700 flex-1" />
	</div>

	<!--
		Deliberately outside the form above and without `use:enhance`. The
		response is a redirect to github.com, and enhance would hand that to
		`goto()`, which cannot navigate off-site.
	-->
	<form method="POST" action="/auth/github">
		<input type="hidden" name="redirectTo" value={page.url.searchParams.get('redirectTo') ?? ''} />
		<button type="submit" class="btn preset-tonal min-w-full" disabled={loading}>
			<Github size={18} />
			<span>Sign up with GitHub</span>
		</button>
	</form>
</div>
