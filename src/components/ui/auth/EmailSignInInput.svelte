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
		email = $bindable(''),
		password = $bindable(''),
		required = false,
		onValidationChange = () => {},
		onPasswordChange = () => {}
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
		class="input"
		name="email"
		placeholder="Email"
		autocomplete="email"
		{required}
		bind:value={email}
	/>

	<div class="relative">
		<input
			id="show-password"
			class="input"
			type={show ? 'text' : 'password'}
			placeholder="Password"
			autocomplete="current-password"
			{required}
			bind:value={password}
		/>
		<button
			type="button"
			aria-label={show ? 'Hide password' : 'Show password'}
			aria-pressed={show}
			class="btn-icon preset-tonal absolute top-1/2 right-1 -translate-y-1/2"
			onclick={() => (show = !show)}
		>
			{#if show}
				<Eye class="h-5 w-5" />
			{:else}
				<EyeOff class="h-5 w-5" />
			{/if}
		</button>
	</div>

	<div class="mt-6 flex items-center justify-center gap-2">
		<span>Not registered?</span>
		<a href="/auth/signup" class="btn preset-filled-secondary-500"> Create an Account </a>
	</div>

	{#if email && !emailValid}
		<p class="text-error-500 mt-1 text-sm">Please enter a valid email address</p>
	{/if}
</div>
