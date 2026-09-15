<script lang="ts">
	import { enhance } from '$app/forms';
	import type { User } from '@supabase/supabase-js';
	import type { SubmitFunction } from '@sveltejs/kit';
	let {
		user,
		error,
		message,
		value
	}: { user: User | null; error?: string; message?: string; value?: string } = $props();
	let busy = $state(false);
	const submit: SubmitFunction = ({ cancel }) => {
		if (busy) {
			cancel();
			return;
		}
		busy = true;
		return async ({ result, update }) => {
			try {
				await update({ reset: result.type === 'success' });
			} finally {
				busy = false;
			}
		};
	};
</script>

<section class="card preset-tonal space-y-4 p-5" aria-busy={busy}>
	<h2 class="h4">Email address</h2>
	<div>
		<p class="text-sm font-medium">Current email</p>
		<p class="break-all">{user?.email ?? 'No email address'}</p>
	</div>
	{#if user?.new_email}
		<div class="space-y-2">
			<p class="text-sm">
				Awaiting confirmation: <strong class="break-all">{user.new_email}</strong>
			</p>
			<p class="text-surface-600-400 text-sm">
				Your current address stays active until the change is confirmed. Check both inboxes and
				follow the latest confirmation instructions.
			</p>
			<form method="POST" use:enhance={submit}>
				<button name="intent" value="emailResend" class="btn preset-tonal" disabled={busy}
					>Resend confirmation</button
				>
			</form>
		</div>
	{/if}
	<form method="POST" use:enhance={submit} class="space-y-3">
		<input type="hidden" name="intent" value="emailChange" />
		<label class="label"
			><span class="label-text">New email address</span><input
				class="input"
				type="email"
				name="email"
				autocomplete="email"
				maxlength="254"
				required
				value={value ?? ''}
				aria-describedby="email-change-help email-change-result"
				disabled={busy}
			/></label
		>
		<label class="label"
			><span class="label-text">Confirm new email address</span><input
				class="input"
				type="email"
				name="emailConfirmation"
				autocomplete="off"
				maxlength="254"
				required
				disabled={busy}
			/></label
		>
		<p id="email-change-help" class="text-surface-600-400 text-sm">
			You’ll receive confirmation instructions before the change takes effect. This changes your
			portal email, not the email held by Google, Microsoft or another sign-in provider.
		</p>
		<button class="btn preset-filled-primary-500" disabled={busy}
			>{busy ? 'Requesting…' : 'Request email change'}</button
		>
	</form>
	<p id="email-change-result" role="status" class="text-sm">{error ?? message ?? ''}</p>
</section>
