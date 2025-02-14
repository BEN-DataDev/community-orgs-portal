<script lang="ts">
	import { enhance } from '$app/forms';
	import EmailSignInInput from '$components/ui/auth/EmailSignInInput.svelte';
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

	let form = $props<{ form: ActionData | null }>();

	const formDefault: FormData = {
		email: '',
		password: '',
		provider: 'email',
		errors: {}
	};

	let formData = $state<FormData>(formDefault);
	let loading = $state(false);

	$effect(() => {
		if (form?.form) {
			const actionData = form.form as unknown as {
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
					formErrors = failureData.errors || { general: failureData.error || 'Sign in failed' };
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

<div class="mx-auto my-2.5 w-[400px] rounded-lg bg-gray-300 p-5 shadow-md dark:bg-gray-400">
	{#if formErrors.general}
		<p class="mb-4 text-red-500">{formErrors.general}</p>
	{/if}
	<form
		id="signInForm"
		action="?/signin"
		method="post"
		class="space-y-3"
		enctype="multipart/form-data"
		use:enhance={handleEnhance}
	>
		<EmailSignInInput
			email={formData.email}
			password={formData.password}
			onValidationChange={handleValidationChange}
			onPasswordChange={(newPassword) => (formData.password = newPassword)}
			required={true}
		/>
		<input type="hidden" name="password" bind:value={formData.password} />
		{#if formErrors.email}
			<p class="text-sm text-red-500">{formErrors.email}</p>
		{/if}
		{#if formErrors.password}
			<p class="text-sm text-red-500">{formErrors.password}</p>
		{/if}
		<input type="hidden" name="provider" bind:value={formData.provider} />
		<button
			type="submit"
			class="btn min-w-full preset-filled-primary-500"
			disabled={!submissionValid || loading}
		>
			{loading ? 'Signing in...' : 'Sign In'}
		</button>
	</form>
</div>
