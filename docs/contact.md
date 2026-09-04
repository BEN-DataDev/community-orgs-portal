/src/routes/organisations/[id]/contact/+page.server.ts

```ts
import { supabase } from '$lib/services/supabase';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ params }) => {
	const { data: contactInfo } = await supabase
		.from('contact_info')
		.select(
			`
            *,
            organisations (
                legal_name,
                trading_name
            )
        `
		)
		.eq('org_id', params.id)
		.single();

	return { contactInfo };
};

export const actions: Actions = {
	updateContact: async ({ request }) => {
		const formData = await request.formData();
		const { orgId, ...contactData } = Object.fromEntries(formData);

		const { data, error } = await supabase
			.from('contact_info')
			.upsert({
				org_id: orgId,
				...contactData
			})
			.select();

		return { success: !error, data };
	}
};
```

/src/routes/organisations/[id]/contact/+page.svelte

```svelte
<script lang="ts">
	import { enhance } from '$app/forms';
	import { Button, Card } from '$lib/components/common';
	import ContactForm from '$lib/components/forms/ContactForm.svelte';

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
		<Button on:click={() => (isEditing = !isEditing)}>
			{isEditing ? 'Cancel' : 'Edit Contact Info'}
		</Button>
	</div>

	{#if isEditing}
		<ContactForm {contactInfo} on:save={() => (isEditing = false)} />
	{:else}
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
			<Card title="Primary Contact">
				<div class="space-y-2">
					<p><strong>Email:</strong> {contactInfo.email}</p>
					<p><strong>Phone:</strong> {contactInfo.phone}</p>
					<p><strong>Website:</strong> {contactInfo.website}</p>
				</div>
			</Card>

			<Card title="Address">
				<div class="space-y-2">
					<p>{contactInfo.street_address}</p>
					<p>{contactInfo.city}, {contactInfo.state} {contactInfo.postal_code}</p>
					<p>{contactInfo.country}</p>
				</div>
			</Card>
		</div>
	{/if}
</div>
```

ContactForm.svelte

```svelte
<script lang="ts">
	import { enhance } from '$app/forms';
	import { Button } from '$lib/components/common';

	interface Props {
		contactInfo: any;
	}

	let { contactInfo }: Props = $props();

	function handleSubmit() {
		dispatch('save');
	}
</script>

<form
	method="POST"
	action="?/updateContact"
	use:enhance={() => {
		return ({ result }) => {
			if (result.type === 'success') {
				handleSubmit();
			}
		};
	}}
	class="space-y-6"
>
	<input type="hidden" name="orgId" value={contactInfo.org_id} />

	<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
		<div>
			<label>Email</label>
			<input type="email" name="email" value={contactInfo.email} required />
		</div>

		<div>
			<label>Phone</label>
			<input type="tel" name="phone" value={contactInfo.phone} required />
		</div>

		<div>
			<label>Website</label>
			<input type="url" name="website" value={contactInfo.website} />
		</div>

		<div>
			<label>Street Address</label>
			<input type="text" name="street_address" value={contactInfo.street_address} required />
		</div>

		<div>
			<label>City</label>
			<input type="text" name="city" value={contactInfo.city} required />
		</div>

		<div>
			<label>State</label>
			<input type="text" name="state" value={contactInfo.state} required />
		</div>

		<div>
			<label>Postal Code</label>
			<input type="text" name="postal_code" value={contactInfo.postal_code} required />
		</div>

		<div>
			<label>Country</label>
			<input type="text" name="country" value={contactInfo.country} required />
		</div>
	</div>

	<div class="flex justify-end">
		<Button type="submit">Save Changes</Button>
	</div>
</form>
```
