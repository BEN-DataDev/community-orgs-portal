<script lang="ts">
	import { Eye, EyeOff } from 'lucide-svelte';

	interface Props {
		email: string;
		password: string;
		required?: boolean;
		onValidationChange: (isValid: boolean) => void;
		onPasswordChange: (password: string) => void;
	}

	let {
		email = '',
		password = '',
		required = false,
		onValidationChange = (valid: boolean) => {},
		onPasswordChange = (pwd: string) => {}
	}: Props = $props();

	let show = $state(false);

	function validateEmail(email: string) {
		const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
		return emailRegex.test(email);
	}

	let emailValid = $derived(validateEmail(email));
	let formValid = $derived(emailValid && password.length >= 6);

	$effect(() => {
		onValidationChange(formValid);
		onPasswordChange(password);
	});
</script>

<div class="space-y-4">
	<h1 class="h1 type-scale-4">Sign In with Email and Password:</h1>

	<input
		type="email"
		class="variant-filled input"
		name="email"
		placeholder="Email"
		autocomplete="email"
		{required}
		bind:value={email}
	/>

	<input
		id="show-password"
		class="variant-filled input"
		type={show ? 'text' : 'password'}
		placeholder="Password"
		autocomplete="current-password"
		{required}
		bind:value={password}
	/>

	{#snippet right()}
		<button
			onclick={(event) => {
				event.preventDefault();
				show = !show;
			}}
			class="variant-ghost btn-icon"
		>
			{#if show}
				<Eye class="h-6 w-6" />
			{:else}
				<EyeOff class="h-6 w-6" />
			{/if}
		</button>
	{/snippet}

	<div class="mt-6 flex items-center justify-center gap-2">
		<span>Not registered?</span>
		<a href="/auth/signup" class="btn preset-filled-secondary-500"> Create an Account </a>
	</div>

	{#if email && !emailValid}
		<p class="mt-1 text-sm text-error-500">Please enter a valid email address</p>
	{/if}
</div>
