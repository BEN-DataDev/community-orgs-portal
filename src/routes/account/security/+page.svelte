<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import { ShieldCheck, ShieldOff } from 'lucide-svelte';
	import { totpCodeSchema } from '$lib/auth/schemas';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	/**
	 * Enrolment has to happen in the browser: `mfa.enroll()` returns the QR code
	 * and the shared secret exactly once, and the secret must never make a second
	 * trip through the server. Verification stays here too, because a successful
	 * `verify` hands the client library a fresh aal2 session that it writes to the
	 * auth cookies itself.
	 */
	const verified = $derived(data.factors.filter((factor) => factor.status === 'verified'));
	const enrolled = $derived(verified.length > 0);

	type Stage = 'idle' | 'enrolling' | 'confirming';

	let stage = $state<Stage>('idle');
	let factorId = $state('');
	let qrCode = $state('');
	let secret = $state('');
	let code = $state('');
	let busy = $state(false);
	let error = $state('');
	let notice = $state('');

	const codeValid = $derived(totpCodeSchema.safeParse({ code }).success);

	function reset() {
		stage = 'idle';
		factorId = '';
		qrCode = '';
		secret = '';
		code = '';
		error = '';
	}

	async function startEnrolment() {
		busy = true;
		error = '';
		notice = '';

		const { data: enrolment, error: enrolError } = await data.supabase.auth.mfa.enroll({
			factorType: 'totp',
			friendlyName: `Authenticator (${new Date().toLocaleDateString('en-AU')})`
		});

		busy = false;

		if (enrolError) {
			console.error('Could not start MFA enrolment:', enrolError.message);
			error = 'Could not start setup. Please try again.';
			return;
		}

		factorId = enrolment.id;
		qrCode = enrolment.totp.qr_code;
		secret = enrolment.totp.secret;
		stage = 'confirming';
	}

	async function confirmEnrolment(event: SubmitEvent) {
		event.preventDefault();
		if (!codeValid || busy) return;

		busy = true;
		error = '';

		try {
			const { data: challenge, error: challengeError } = await data.supabase.auth.mfa.challenge({
				factorId
			});
			if (challengeError) throw challengeError;

			const { error: verifyError } = await data.supabase.auth.mfa.verify({
				factorId,
				challengeId: challenge.id,
				code
			});

			if (verifyError) {
				error = 'That code was not accepted. Check the app and try the next code it shows.';
				code = '';
				return;
			}

			reset();
			notice = 'Two-factor authentication is on for this account.';
			await invalidateAll();
		} catch (thrown) {
			console.error('MFA enrolment failed:', thrown);
			error = 'Something went wrong. Please try again.';
		} finally {
			busy = false;
		}
	}

	async function cancelEnrolment() {
		/**
		 * An unverified factor left behind still counts against the enrolment
		 * limit, so abandoning setup removes it rather than orphaning it.
		 */
		if (factorId) {
			await data.supabase.auth.mfa.unenroll({ factorId });
		}
		reset();
		await invalidateAll();
	}

	async function remove(id: string) {
		if (!confirm('Turn off two-factor authentication for this account?')) return;

		busy = true;
		error = '';

		const { error: unenrolError } = await data.supabase.auth.mfa.unenroll({ factorId: id });

		if (unenrolError) {
			console.error('Could not remove MFA factor:', unenrolError.message);
			error = 'Could not turn it off. Please try again.';
			busy = false;
			return;
		}

		/**
		 * Without this the session keeps its aal2 claim until the next scheduled
		 * refresh, so the account would still be treated as MFA-protected for up
		 * to an hour after the factor was removed.
		 */
		await data.supabase.auth.refreshSession();
		notice = 'Two-factor authentication is off.';
		busy = false;
		await invalidateAll();
	}
</script>

<svelte:head>
	<title>Security</title>
</svelte:head>

<div class="mx-auto my-4 w-full max-w-2xl space-y-4 p-4">
	<h1 class="h2">Security</h1>

	{#if notice}
		<p class="text-success-500">{notice}</p>
	{/if}
	{#if error}
		<p class="text-error-500">{error}</p>
	{/if}

	<section class="card preset-tonal space-y-4 p-5 shadow-md">
		<header class="flex items-start gap-3">
			{#if enrolled}
				<ShieldCheck class="text-success-500 mt-1 h-6 w-6 shrink-0" />
			{:else}
				<ShieldOff class="text-surface-600-400 mt-1 h-6 w-6 shrink-0" />
			{/if}
			<div>
				<h2 class="h4">Two-factor authentication</h2>
				<p class="text-surface-700-300 text-sm">
					{#if enrolled}
						On. You will be asked for a code from your authenticator app each time you sign in.
					{:else}
						Off. Adding an authenticator app means a stolen password is not enough to get into your
						account.
					{/if}
				</p>
			</div>
		</header>

		{#if stage === 'confirming'}
			<div class="space-y-4">
				<p class="text-sm">
					Scan this with Google Authenticator, Authy, 1Password or any other authenticator app.
				</p>

				<!-- Supabase returns the QR as an SVG data URL, ready for a plain img. -->
				<img
					src={qrCode}
					alt="QR code for setting up two-factor authentication"
					class="bg-surface-50 mx-auto h-48 w-48 rounded p-2"
				/>

				<details class="text-sm">
					<summary class="cursor-pointer">Can't scan it?</summary>
					<p class="mt-2">Enter this key into your app by hand:</p>
					<code class="bg-surface-200-700 mt-1 block rounded p-2 font-mono text-xs break-all"
						>{secret}</code
					>
				</details>

				<form class="space-y-3" onsubmit={confirmEnrolment}>
					<label class="label">
						<span class="label-text">Enter the code your app shows</span>
						<input
							class="input text-center font-mono text-2xl tracking-[0.4em]"
							type="text"
							inputmode="numeric"
							autocomplete="one-time-code"
							maxlength="6"
							placeholder="000000"
							bind:value={code}
						/>
					</label>

					<div class="flex gap-2">
						<button
							type="submit"
							class="btn preset-filled-primary-500 flex-1"
							disabled={!codeValid || busy}
						>
							{busy ? 'Checking...' : 'Turn on'}
						</button>
						<button
							type="button"
							class="btn preset-tonal"
							onclick={cancelEnrolment}
							disabled={busy}
						>
							Cancel
						</button>
					</div>
				</form>
			</div>
		{:else if enrolled}
			<ul class="space-y-2">
				{#each verified as factor (factor.id)}
					<li class="border-surface-300-700 flex items-center justify-between border-t pt-2">
						<div>
							<p class="text-sm font-medium">{factor.friendlyName}</p>
							<p class="text-surface-600-400 text-xs">
								Added {new Date(factor.createdAt).toLocaleDateString('en-AU')}
							</p>
						</div>
						<button
							type="button"
							class="btn btn-sm preset-tonal"
							onclick={() => remove(factor.id)}
							disabled={busy}
						>
							Turn off
						</button>
					</li>
				{/each}
			</ul>
		{:else}
			<button
				type="button"
				class="btn preset-filled-primary-500"
				onclick={startEnrolment}
				disabled={busy}
			>
				{busy ? 'Setting up...' : 'Set up authenticator app'}
			</button>
		{/if}
	</section>
</div>
