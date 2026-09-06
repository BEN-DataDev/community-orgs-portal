<script lang="ts">
	import ContactForm from '$components/forms/ContactForm.svelte';
	import { EDITOR_LEVEL } from '$lib/role-levels';

	let { data, form } = $props();
	let { contactInfo, organisation, roleLevel } = $derived(data);
	let canEdit = $derived(roleLevel >= EDITOR_LEVEL);
	let isEditing = $state(false);

	/** `phone` is a jsonb column, stored as `{ primary: "..." }`. */
	let phone = $derived.by(() => {
		const value = contactInfo?.phone;
		if (value && typeof value === 'object' && 'primary' in value) {
			const primary = (value as { primary?: unknown }).primary;
			if (typeof primary === 'string') return primary;
		}
		return '—';
	});
</script>

<div>
	<div class="mb-6 flex flex-wrap items-start justify-between gap-3">
		<div>
			<h1 class="text-2xl font-bold">Contact Information</h1>
			<p class="text-surface-600-400">{organisation.entity_name}</p>
		</div>
		{#if canEdit}
			<button class="btn preset-filled" onclick={() => (isEditing = !isEditing)}>
				{isEditing ? 'Cancel' : 'Edit Contact Info'}
			</button>
		{/if}
	</div>

	{#if form?.message}
		<p class="text-error-500 mb-4">{form.message}</p>
	{/if}

	{#if isEditing && canEdit}
		<ContactForm {contactInfo} errors={form?.errors} onSave={() => (isEditing = false)} />
	{:else if contactInfo}
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2 xl:gap-8">
			<div class="card preset-outlined-surface-200-800 space-y-2 p-4">
				<h2 class="font-medium">Primary Contact</h2>
				<p><strong>Email:</strong> {contactInfo.email ?? '—'}</p>
				<p><strong>Phone:</strong> {phone}</p>
				<p><strong>Website:</strong> {contactInfo.website ?? '—'}</p>
			</div>

			<div class="card preset-outlined-surface-200-800 space-y-2 p-4">
				<h2 class="font-medium">Addresses</h2>
				<p><strong>Physical:</strong> {contactInfo.physical_address ?? '—'}</p>
				<p><strong>Postal:</strong> {contactInfo.postal_address ?? '—'}</p>
			</div>
		</div>
	{:else}
		<p class="text-surface-600-400">No contact details recorded yet.</p>
	{/if}
</div>
