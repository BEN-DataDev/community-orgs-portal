<script lang="ts">
	import { enhance } from '$app/forms';
	import { invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import type { SubmitFunction } from '@sveltejs/kit';
	import { sessionBrowser, sessionTime, type AccountSession } from '$lib/account-sessions';
	let {
		sessions,
		error,
		message
	}: { sessions: AccountSession[] | null; error?: string; message?: string } = $props();
	let busy = $state(false);
	let refreshError = $state('');
	const total = $derived(sessions?.[0]?.total_count ?? 0);
	const submit: SubmitFunction = ({ cancel }) => {
		if (busy) {
			cancel();
			return;
		}
		busy = true;
		return async ({ update }) => {
			try {
				await update();
			} finally {
				busy = false;
			}
		};
	};
	async function refresh() {
		busy = true;
		refreshError = '';
		try {
			await invalidateAll();
		} catch {
			refreshError = 'Could not refresh sessions. Please try again.';
		} finally {
			busy = false;
		}
	}
</script>

<section class="card preset-tonal space-y-4 p-5" aria-busy={busy}>
	<div class="flex flex-wrap items-center justify-between gap-2">
		<h2 class="h4">Devices &amp; sessions</h2>
		<button type="button" class="btn btn-sm preset-tonal" onclick={refresh} disabled={busy}
			>Refresh sessions</button
		>
	</div>
	<p class="text-surface-600-400 text-sm">
		Each sign-in creates a session. Browser details may be unavailable, and refresh times do not
		indicate whether a device is online.
	</p>
	<p role="status" class="text-sm">{refreshError || error || message || ''}</p>
	{#if sessions === null}
		<p>We couldn’t load your sessions. Refresh to try again.</p>
	{:else if sessions.length === 0}
		<p>No sessions could be found. Refresh the page or sign in again.</p>
	{:else}
		{#if total > sessions.length}<p class="text-sm">
				Showing {sessions.length} of {total} sessions. Bulk sign-out includes all sessions.
			</p>{/if}
		<ul class="space-y-4">
			{#each sessions as session (session.session_id)}
				<li class="border-surface-200-800 space-y-2 border-t pt-4">
					<div class="flex flex-wrap items-center gap-2">
						<span class="font-medium">{sessionBrowser(session.user_agent)}</span
						>{#if session.is_current}<span class="badge preset-tonal-primary">This session</span
							>{/if}
					</div>
					<dl class="text-surface-600-400 text-sm">
						<div>
							<dt class="inline font-medium">Signed in:</dt>
							<dd class="inline">{sessionTime(session.signed_in_at)}</dd>
						</div>
						<div>
							<dt class="inline font-medium">Last refreshed:</dt>
							<dd class="inline">{sessionTime(session.last_refreshed_at)}</dd>
						</div>
						{#if session.expires_at}<div>
								<dt class="inline font-medium">Expires:</dt>
								<dd class="inline">{sessionTime(session.expires_at)}</dd>
							</div>{/if}
					</dl>
					{#if session.is_current}
						<a class="btn btn-sm preset-tonal" href={resolve('/auth/signout')}
							>Sign out this session</a
						>
					{:else}
						<form method="POST" use:enhance={submit}>
							<input type="hidden" name="intent" value="revokeSession" />
							<input type="hidden" name="sessionId" value={session.session_id} />
							<button
								class="btn btn-sm preset-tonal"
								disabled={busy}
								aria-label={`Sign out ${sessionBrowser(session.user_agent)}, signed in ${sessionTime(session.signed_in_at)}`}
								>Sign out session</button
							>
						</form>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
	<div class="border-surface-200-800 space-y-3 border-t pt-4">
		<form method="POST" use:enhance={submit}>
			<button
				name="intent"
				value="signOutOthers"
				class="btn preset-tonal"
				disabled={busy || sessions === null || total < 2}>Sign out other sessions</button
			>
		</form>
		<details>
			<summary class="cursor-pointer text-sm underline">Sign out everywhere</summary>
			<p class="my-3 text-sm">
				This includes your current session. You will need to sign in again.
			</p>
			<form method="POST" use:enhance={submit}>
				<button
					name="intent"
					value="signOutAll"
					class="btn preset-filled-error-500"
					disabled={busy || sessions === null}>Confirm sign out everywhere</button
				>
			</form>
		</details>
	</div>
	<p class="text-surface-600-400 text-sm">
		Signing out prevents session renewal. Already-issued access tokens may continue working until
		they expire.
	</p>
</section>
