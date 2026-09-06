<script lang="ts">
	import { resolve } from '$app/paths';
	import { Eye, EyeOff } from 'lucide-svelte';
	import { isValidEmail, passwordProblems } from '$lib/auth/schemas';
	import PasswordStrengthMeter from './PasswordStrengthMeter.svelte';

	interface Props {
		email: string;
		password: string;
		required?: boolean;
		onValidationChange: (matches: boolean) => void;
	}

	let {
		email = $bindable(''),
		password = $bindable(''),
		required = false,
		onValidationChange = () => {}
	}: Props = $props();

	let show = $state(false);
	let showAgain = $state(false);

	let passwordConfirmation = $state('');
	let passwordsMatch = $derived(password === passwordConfirmation && password !== '');
	let emailValid = $derived(isValidEmail(email));

	/**
	 * The zxcvbn meter below is advice; these are the rules the server and GoTrue
	 * will actually enforce. Showing them here means the submit button and the
	 * server agree on what is acceptable.
	 */
	let problems = $derived(passwordProblems(password));

	$effect(() => {
		onValidationChange(passwordsMatch && emailValid && problems.length === 0);
	});
</script>

<div class="space-y-4">
	<h1 class="h3">Create an account</h1>

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
			id="show-password1"
			class="input"
			type={show ? 'text' : 'password'}
			name="password"
			placeholder="Password"
			autocomplete="new-password"
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

	<PasswordStrengthMeter {password} />

	<div class="relative">
		<input
			id="show-passwordAgain"
			class="input"
			type={showAgain ? 'text' : 'password'}
			placeholder="Password Again"
			autocomplete="new-password"
			{required}
			bind:value={passwordConfirmation}
		/>
		<button
			type="button"
			aria-label={showAgain ? 'Hide password confirmation' : 'Show password confirmation'}
			aria-pressed={showAgain}
			class="btn-icon preset-tonal absolute top-1/2 right-1 -translate-y-1/2"
			onclick={() => (showAgain = !showAgain)}
		>
			{#if showAgain}
				<Eye class="h-5 w-5" />
			{:else}
				<EyeOff class="h-5 w-5" />
			{/if}
		</button>
	</div>

	{#if email && !emailValid}
		<p class="text-error-500 mt-1 text-sm">Please enter a valid email address</p>
	{/if}

	{#if password && problems.length > 0}
		<ul class="text-error-500 mt-1 space-y-0.5 text-sm">
			{#each problems as problem (problem)}
				<li>{problem}</li>
			{/each}
		</ul>
	{/if}

	{#if password && passwordConfirmation && !passwordsMatch}
		<p class="text-error-500 mt-1 text-sm">Passwords do not match</p>
	{/if}

	<div class="mt-6 flex items-center justify-center gap-2">
		<span>Have an account?</span>
		<a href={resolve('/auth/signin')} class="btn preset-filled">Sign In</a>
	</div>
</div>
