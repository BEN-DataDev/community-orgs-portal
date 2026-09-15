<script lang="ts">
	import { enhance } from '$app/forms';
	import { resolve } from '$app/paths';
	import EmailSettings from '$components/ui/EmailSettings.svelte';
	import AvatarSettings from '$components/ui/AvatarSettings.svelte';
	import AppearancePicker from '$components/ui/AppearancePicker.svelte';
	import { displayName } from '$lib/account';
	import type { PageProps } from './$types';
	let { data, form }: PageProps = $props();
	let busy = $state(false);
</script>

<svelte:head><title>Account settings</title></svelte:head>

<div class="mx-auto w-full max-w-2xl space-y-6">
	<header>
		<h1 class="h2">Account settings</h1>
		<p class="text-surface-600-400">Manage your profile, appearance and organisation access.</p>
	</header>
	<AvatarSettings avatar={data.avatar} name={displayName(data.user)} />
	<p role="status" class="text-sm">
		{form?.error ?? form?.message ?? (form?.success ? 'Display name saved.' : '')}
	</p>
	<section class="card preset-tonal space-y-4 p-5">
		<h2 class="h4">Profile</h2>
		<form
			method="POST"
			class="space-y-4"
			use:enhance={() => {
				busy = true;
				return async ({ update }) => {
					try {
						await update({ reset: false });
					} finally {
						busy = false;
					}
				};
			}}
		>
			<label class="label"
				><span class="label-text">Display name</span><input
					class="input"
					name="displayName"
					autocomplete="name"
					required
					maxlength="80"
					value={displayName(data.user)}
				/></label
			>
			<button class="btn preset-filled-primary-500" disabled={busy}
				>{busy ? 'Saving…' : 'Save changes'}</button
			>
		</form>
	</section>
	<EmailSettings
		user={data.user}
		error={form?.emailError}
		message={form?.emailMessage}
		value={form?.emailValue}
	/>
	<section class="card preset-tonal p-5"><AppearancePicker /></section>
	<section id="access" class="card preset-tonal space-y-4 p-5">
		<h2 class="h4">My access</h2>
		<p class="text-surface-600-400 text-sm">Your roles apply to each organisation individually.</p>
		{#if data.memberships === null}
			<p role="status">We couldn’t load your access. Reload this page to try again.</p>
		{:else if data.memberships.length === 0}
			<p>You don’t have any organisation roles yet. You can browse public organisations.</p>
		{:else}
			<ul class="space-y-3">
				{#each data.memberships as org (org.organisation_id)}
					<li class="border-surface-200-800 space-y-2 border-t pt-3">
						<a
							class="block font-medium break-words hover:underline"
							href={resolve('/organisations/[id]', { id: org.organisation_id })}
							>{org.organisation_name}</a
						>
						<div class="flex flex-wrap gap-2">
							{#each org.role_names as role (role)}<span class="badge preset-tonal-primary"
									>{role}</span
								>{/each}
						</div>
					</li>
				{/each}
			</ul>
		{/if}
	</section>
	<a class="btn preset-tonal" href={resolve('/account/security')}>Security & sign-in</a>
</div>
