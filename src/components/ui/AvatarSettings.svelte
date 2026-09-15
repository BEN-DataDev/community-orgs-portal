<script lang="ts">
	import { Avatar } from '@skeletonlabs/skeleton-svelte';
	import { enhance } from '$app/forms';
	import { AVATAR_MAX_BYTES, AVATAR_MIME_TYPES, type AccountAvatar } from '$lib/avatar';
	import type { SubmitFunction } from '@sveltejs/kit';

	let { avatar, name }: { avatar: AccountAvatar | null; name: string } = $props();
	let busy = $state(false);
	let files = $state<FileList>();
	let preview = $state<string | null>(null);
	const selected = $derived(files?.[0]);
	const error = $derived(
		selected && (selected.size > AVATAR_MAX_BYTES || !AVATAR_MIME_TYPES.includes(selected.type))
			? 'Choose a JPEG, PNG or WebP image smaller than 2 MB.'
			: ''
	);
	const initials = $derived(
		name
			.split(/\s+/)
			.slice(0, 2)
			.map((part) => Array.from(part)[0])
			.join('')
			.toUpperCase()
	);

	// Blob URLs need explicit cleanup when the selection changes or unmounts.
	$effect(() => {
		if (!selected || error) {
			preview = null;
			return;
		}
		const url = URL.createObjectURL(selected);
		preview = url;
		return () => URL.revokeObjectURL(url);
	});

	const submit: SubmitFunction = ({ cancel }) => {
		if (busy) {
			cancel();
			return;
		}
		busy = true;
		return async ({ result, update }) => {
			try {
				await update({ reset: result.type === 'success' });
				if (result.type === 'success') files = undefined;
			} finally {
				busy = false;
			}
		};
	};
</script>

<section class="card preset-tonal space-y-4 p-5" aria-busy={busy}>
	<h2 class="h4">Profile photo</h2>
	<Avatar class="preset-tonal-primary size-24 overflow-hidden rounded-full">
		{#if preview ?? avatar?.url}<Avatar.Image
				src={preview ?? avatar?.url ?? ''}
				alt={preview ? 'Selected photo preview' : 'Your profile photo'}
				referrerpolicy="no-referrer"
				class="size-full object-cover"
			/>{/if}
		<Avatar.Fallback class="flex size-full items-center justify-center text-2xl font-semibold"
			>{initials}</Avatar.Fallback
		>
	</Avatar>
	{#if !avatar?.available}
		<p role="status">Your photo settings are unavailable. Reload the page to try again.</p>
	{/if}
	<form method="POST" enctype="multipart/form-data" use:enhance={submit} class="space-y-3">
		<input type="hidden" name="intent" value="uploadAvatar" />
		<input type="hidden" name="avatarRevision" value={avatar?.revision ?? 0} />
		<label class="label">
			<span class="label-text">Choose a photo</span>
			<input
				type="file"
				name="avatar"
				accept="image/jpeg,image/png,image/webp"
				bind:files
				required
				disabled={busy || !avatar?.available}
				aria-describedby="avatar-help avatar-error"
				class="input max-w-full"
			/>
		</label>
		<p id="avatar-help" class="text-surface-600-400 text-sm">
			JPEG, PNG or WebP, up to 2 MB. Your photo is saved to your account for every sign-in method.
		</p>
		<p id="avatar-error" role="status" class="text-sm">{error}</p>
		<button class="btn preset-filled-primary-500" disabled={busy || !!error || !avatar?.available}
			>{busy ? 'Saving…' : avatar?.source === 'upload' ? 'Replace photo' : 'Upload photo'}</button
		>
	</form>
	<form method="POST" use:enhance={submit} class="flex flex-wrap gap-2">
		<input type="hidden" name="avatarRevision" value={avatar?.revision ?? 0} />
		{#if avatar?.canImportProvider}
			<button
				name="intent"
				value="importAvatar"
				class="btn preset-tonal"
				disabled={busy || !avatar?.available}>Save provider photo</button
			>
		{/if}
		{#if avatar?.hasProviderPhoto && avatar.source !== 'provider'}
			<button
				name="intent"
				value="providerAvatar"
				class="btn preset-tonal"
				disabled={busy || !avatar?.available}>Use provider photo</button
			>
		{/if}
		{#if avatar?.url || avatar?.source === 'upload'}
			<button
				name="intent"
				value="removeAvatar"
				class="btn preset-tonal"
				disabled={busy || !avatar?.available}>Remove photo</button
			>
		{/if}
	</form>
	<p class="text-surface-600-400 text-sm">
		Remove photo uses your initials.
		{#if avatar?.hasProviderPhoto}Save provider photo keeps a copy here; Use provider photo follows
			the external image.{/if}
	</p>
</section>
