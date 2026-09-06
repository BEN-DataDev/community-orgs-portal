<script lang="ts">
	import { resolve } from '$app/paths';
	import { Eye, EyeOff } from 'lucide-svelte';
	import { isValidEmail } from '$lib/auth/schemas';

	interface Props {
		email: string;
		password: string;
		required?: boolean;
		onValidationChange: (isValid: boolean) => void;
	}

	let {
		email = $bindable(''),
		password = $bindable(''),
		required = false,
		onValidationChange = () => {}
	}: Props = $props();

	let show = $state(false);

	let emailValid = $derived(isValidEmail(email));

	/**
	 * Sign-in only checks that a password was typed. Applying the sign-up
	 * strength rules here would reject valid older passwords and advertise the
	 * policy at the sign-in prompt, where it helps nobody get in.
	 */
	let formValid = $derived(emailValid && password.length > 0);

	$effect(() => {
		onValidationChange(formValid);
	});
</script>

<div class="space-y-4">
	<h1 class="h3">Sign in</h1>

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
			name="password"
			placeholder="Password"
			autocomplete="current-password"
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

	<div class="flex justify-end">
		<a href={resolve('/auth/forgot-password')} class="anchor text-sm">Forgot your password?</a>
	</div>

	{#if email && !emailValid}
		<p class="text-error-500 mt-1 text-sm">Please enter a valid email address</p>
	{/if}
</div>
