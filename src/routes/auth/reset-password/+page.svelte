<script lang="ts">
	import { enhance } from '$app/forms';
	import { Eye, EyeOff } from 'lucide-svelte';
	import PasswordStrengthMeter from '$components/ui/auth/PasswordStrengthMeter.svelte';
	import { createAuthForm } from '$lib/auth/form.svelte';
	import { passwordProblems } from '$lib/auth/schemas';

	let password = $state('');
	let passwordConfirmation = $state('');
	let show = $state(false);
	let showAgain = $state(false);

	const form = createAuthForm();

	const problems = $derived(passwordProblems(password));
	const passwordsMatch = $derived(password === passwordConfirmation && password !== '');
	const canSubmit = $derived(problems.length === 0 && passwordsMatch);
</script>

<svelte:head>
	<title>Set a new password</title>
</svelte:head>

<div class="card preset-tonal mx-auto my-4 w-full max-w-100 space-y-3 p-5 shadow-md">
	<h1 class="h3">Set a new password</h1>

	{#if form.errors.general}
		<p class="text-error-500">{form.errors.general}</p>
	{/if}

	<form action="?/update" method="post" class="space-y-4" use:enhance={form.enhance}>
		<div class="relative">
			<input
				id="new-password"
				class="input"
				type={show ? 'text' : 'password'}
				name="password"
				placeholder="New password"
				autocomplete="new-password"
				required
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
				id="new-password-again"
				class="input"
				type={showAgain ? 'text' : 'password'}
				name="passwordConfirmation"
				placeholder="New password again"
				autocomplete="new-password"
				required
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

		{#if password && problems.length > 0}
			<ul class="text-error-500 space-y-0.5 text-sm">
				{#each problems as problem (problem)}
					<li>{problem}</li>
				{/each}
			</ul>
		{/if}

		{#if password && passwordConfirmation && !passwordsMatch}
			<p class="text-error-500 text-sm">Passwords do not match</p>
		{/if}
		{#if form.errors.password}
			<p class="text-error-500 text-sm">{form.errors.password}</p>
		{/if}

		<button
			type="submit"
			class="btn preset-filled-primary-500 min-w-full"
			disabled={!canSubmit || form.loading}
		>
			{form.loading ? 'Saving...' : 'Save new password'}
		</button>
	</form>
</div>
