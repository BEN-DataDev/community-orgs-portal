<script lang="ts">
	import ContactForm from '$components/forms/ContactForm.svelte';

	let { data } = $props();

	let { contactInfo } = $derived(data);
	let isEditing = $state(false);
</script>

<div class="container mx-auto px-4 py-8">
	<div class="mb-6 flex items-center justify-between">
		<div>
			<h1 class="text-2xl font-bold">Contact Information</h1>
			<p class="text-gray-600">{contactInfo.organisations.legal_name}</p>
		</div>
		<button class="variant-filled btn" onclick={() => (isEditing = !isEditing)}>
			{isEditing ? 'Cancel' : 'Edit Contact Info'}
		</button>
	</div>

	{#if isEditing}
		<ContactForm {contactInfo} onSave={() => (isEditing = false)} />
	{:else}
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
			<card title="Primary Contact">
				<div class="space-y-2">
					<p><strong>Email:</strong> {contactInfo.email}</p>
					<p><strong>Phone:</strong> {contactInfo.phone}</p>
					<p><strong>Website:</strong> {contactInfo.website}</p>
				</div>
			</card>

			<card title="Address">
				<div class="space-y-2">
					<p>{contactInfo.street_address}</p>
					<p>{contactInfo.city}, {contactInfo.state} {contactInfo.postal_code}</p>
					<p>{contactInfo.country}</p>
				</div>
			</card>
		</div>
	{/if}
</div>
