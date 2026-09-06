<script lang="ts">
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
		email = $bindable(''),
		password = $bindable(''),
		required = false,
		onValidationChange = () => {},
		onPasswordChange = () => {}
	}: Props = $props();

	let passwordStrength = $state('');
	let passwordStrengthClass = $state('');

	/**
	 * The zxcvbn dictionaries are several hundred kilobytes of word lists. They
	 * are only needed once someone actually types a password, so they are pulled
	 * in with a dynamic `import()` on the first keystroke instead of riding
	 * along in the sign-up route's initial bundle.
	 */
	let scorer: Promise<(password: string) => { score: number }> | null = null;

	async function loadScorer() {
		const [core, common, en] = await Promise.all([
			import('@zxcvbn-ts/core'),
			import('@zxcvbn-ts/language-common'),
			import('@zxcvbn-ts/language-en')
		]);

		core.zxcvbnOptions.setOptions({
			translations: en.translations,
			graphs: common.adjacencyGraphs,
			dictionary: { ...common.dictionary, ...en.dictionary }
		});

		return core.zxcvbn;
	}

	let show = $state(false);
	let showAgain = $state(false);

	function validateEmail(email: string) {
		const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
		return emailRegex.test(email);
	}

	async function updatePasswordStrength() {
		scorer ??= loadScorer();

		/**
		 * Remember what was typed when this call started: the dictionaries load
		 * asynchronously, so a slower earlier keystroke must not overwrite the
		 * verdict for what is in the field now.
		 */
		const scored = password;
		const zxcvbn = await scorer;
		if (scored !== password) return;

		const strength = zxcvbn(password).score;
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
			placeholder="Password"
			autocomplete="current-password"
			{required}
			bind:value={password}
			oninput={updatePasswordStrength}
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

	<div class="mt-2 mb-4">
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
		<div class="bg-surface-300-600 h-2.5 w-full rounded-full">
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

	<div class="relative">
		<input
			id="show-passwordAgain"
			class="input"
			type={showAgain ? 'text' : 'password'}
			placeholder="Password Again"
			autocomplete="current-password"
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

	<div class="mt-6 flex items-center justify-center gap-2">
		<span>Have an account?</span>
		<a href="/auth/signin" class="btn preset-filled"> Sign In </a>
	</div>

	{#if password && passwordConfirmation && !passwordsMatch}
		<p class="text-error-500 mt-1 text-sm">Passwords do not match</p>
	{/if}
</div>
