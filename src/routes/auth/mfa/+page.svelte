<script lang="ts">
	import { goto, invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { totpCodeSchema } from '$lib/auth/schemas';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	/**
	 * Challenge and verify run in the browser rather than through a form action.
	 * A successful `verify` hands the client library a fresh aal2 session, which
	 * it writes to the auth cookies itself; doing the same server-side would mean
	 * threading the new session back out by hand. `invalidateAll()` is what makes
	 * the server loads re-run against the upgraded token.
	 */
	let code = $state('');
	let submitting = $state(false);
	let error = $state('');

	const codeValid = $derived(totpCodeSchema.safeParse({ code }).success);

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (!codeValid || submitting) return;

		submitting = true;
		error = '';

		try {
			const { data: factors, error: listError } = await data.supabase.auth.mfa.listFactors();
			if (listError) throw listError;

			const factor = factors.totp[0];
			if (!factor) {
				error = 'No authenticator app is set up on this account.';
				return;
			}

			const { data: challenge, error: challengeError } = await data.supabase.auth.mfa.challenge({
				factorId: factor.id
			});
			if (challengeError) throw challengeError;

			const { error: verifyError } = await data.supabase.auth.mfa.verify({
				factorId: factor.id,
				challengeId: challenge.id,
				code
			});
			if (verifyError) {
				/**
				 * Almost always a mistyped or expired code. Codes are valid for one
				 * 30-second interval, with one interval of clock skew allowed.
				 */
				error = 'That code was not accepted. Check your authenticator app and try again.';
				code = '';
				return;
			}

			await invalidateAll();
			await goto(data.redirectTo);
		} catch (thrown) {
			console.error('MFA challenge failed:', thrown);
			error = 'Something went wrong. Please try again.';
		} finally {
			submitting = false;
		}
	}
</script>

<svelte:head>
	<title>Two-factor authentication</title>
</svelte:head>

<div class="card preset-tonal mx-auto my-4 w-full max-w-100 space-y-3 p-5 shadow-md">
	<h1 class="h3">Enter your code</h1>
	<p class="text-surface-700-300 text-sm">
		Open your authenticator app and enter the six-digit code it shows for this account.
	</p>

	{#if error}
		<p class="text-error-500 text-sm">{error}</p>
	{/if}

	<form class="space-y-3" onsubmit={submit}>
		<input
			class="input text-center font-mono text-2xl tracking-[0.4em]"
			type="text"
			inputmode="numeric"
			autocomplete="one-time-code"
			maxlength="6"
			placeholder="000000"
			aria-label="Six-digit authentication code"
			bind:value={code}
		/>

		<button
			type="submit"
			class="btn preset-filled-primary-500 min-w-full"
			disabled={!codeValid || submitting}
		>
			{submitting ? 'Verifying...' : 'Verify'}
		</button>
	</form>

	<p class="text-surface-600-400 text-center text-xs">
		Lost access to your authenticator app? An owner or admin of your organisation can help — or
		<a class="anchor" href={resolve('/auth/signout')}>sign out</a> and start again.
	</p>
</div>
