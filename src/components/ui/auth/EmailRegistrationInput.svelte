<script lang="ts">
	import { zxcvbn, zxcvbnOptions } from '@zxcvbn-ts/core';
	import * as zxcvbnCommonPackage from '@zxcvbn-ts/language-common';
	import * as zxcvbnEnPackage from '@zxcvbn-ts/language-en';
	import { Eye, EyeOff } from 'lucide-svelte';

	interface Props {
		email: string;
		password: string;
		required?: boolean;
		onValidationChange: (matches: boolean) => void;
		onPasswordChange: (password: string) => void;
		// Add any events you were dispatching as callback props
	}

	let {
		email = '',
		password = '',
		required = false,
		onValidationChange = (valid: boolean) => {},
		onPasswordChange = (pwd: string) => {}
	}: Props = $props();

	let passwordStrength = $state('');
	let passwordStrengthClass = $state('');

	const { translations } = zxcvbnEnPackage;
	const { adjacencyGraphs: graphs, dictionary: commonDictionary } = zxcvbnCommonPackage;
	const { dictionary: englishDictionary } = zxcvbnEnPackage;

	const options = {
		translations,
		graphs,
		dictionary: { ...commonDictionary, ...englishDictionary }
	};

	zxcvbnOptions.setOptions(options);

	let show = $state(false);
	let showAgain = $state(false);

	function validateEmail(email: string) {
		const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
		return emailRegex.test(email);
	}

	function updatePasswordStrength() {
		const result = zxcvbn(password);
		const strength = result.score;
		switch (strength) {
			case 0:
				passwordStrength = 'Weak';
				passwordStrengthClass = 'weak';
				break;
			case 1:
				passwordStrength = 'Fair';
				passwordStrengthClass = 'fair';
				break;
			case 2:
				passwordStrength = 'Good';
				passwordStrengthClass = 'good';
				break;
			case 3:
			case 4:
				passwordStrength = 'Strong';
				passwordStrengthClass = 'strong';
				break;
			default:
				passwordStrength = '';
				passwordStrengthClass = '';
		}
	}

	let passwordConfirmation = $state('');
	let passwordsMatch = $derived(password === passwordConfirmation && password !== '');
	let emailValid = $derived(validateEmail(email));

	$effect(() => {
		onValidationChange(passwordsMatch && emailValid);
		onPasswordChange(password);
	});
</script>

<div class="space-y-4">
	<h1 class="h1 type-scale-4">Register with Email and Password:</h1>

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
		id="show-password1"
		class="variant-filled input"
		type={show ? 'text' : 'password'}
		placeholder="Password"
		autocomplete="current-password"
		{required}
		bind:value={password}
		oninput={updatePasswordStrength}
	/>

	{#snippet left()}
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

	<div class="mb-4 mt-2">
		<div class="mb-1 flex justify-between">
			<span class="text-sm font-medium">Password strength</span>
			<span
				class="text-sm font-medium"
				class:text-error-500={passwordStrengthClass === 'weak'}
				class:text-warning-500={passwordStrengthClass === 'fair'}
				class:text-tertiary-500={passwordStrengthClass === 'good'}
				class:text-success-500={passwordStrengthClass === 'strong'}
			>
				{passwordStrength}
			</span>
		</div>
		<div class="bg-surface-300-600-token h-2.5 w-full rounded-full">
			<div
				class="h-2.5 rounded-full transition-all duration-300 ease-in-out"
				class:bg-error-500={passwordStrengthClass === 'weak'}
				class:bg-warning-500={passwordStrengthClass === 'fair'}
				class:bg-tertiary-500={passwordStrengthClass === 'good'}
				class:bg-success-500={passwordStrengthClass === 'strong'}
				style="width: {passwordStrength === 'Weak'
					? 25
					: passwordStrength === 'Fair'
						? 50
						: passwordStrength === 'Good'
							? 75
							: passwordStrength === 'Strong'
								? 100
								: 0}%"
			></div>
		</div>
	</div>

	<input
		id="show-passwordAgain"
		class="variant-filled input"
		type={showAgain ? 'text' : 'password'}
		placeholder="Password Again"
		autocomplete="current-password"
		{required}
		bind:value={passwordConfirmation}
	/>

	{#snippet right()}
		<button
			onclick={(event) => {
				event.preventDefault();
				showAgain = !showAgain;
			}}
			class="variant-ghost btn-icon"
		>
			{#if showAgain}
				<Eye class="h-6 w-6" />
			{:else}
				<EyeOff class="h-6 w-6" />
			{/if}
		</button>
	{/snippet}

	<div class="mt-6 flex items-center justify-center gap-2">
		<span>Have an account?</span>
		<a href="/auth/signin" class="btn preset-filled"> Sign In </a>
	</div>

	{#if password && passwordConfirmation && !passwordsMatch}
		<p class="mt-1 text-sm text-error-500">Passwords do not match</p>
	{/if}
</div>
