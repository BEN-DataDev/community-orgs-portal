<script lang="ts">
	import { enhance } from '$app/forms';
	import type { Database } from '$lib/db.types';

	type ContactInfo = Database['community_orgs']['Tables']['contact_info']['Row'];

	interface Props {
		contactInfo: ContactInfo | null;
		errors?: Record<string, string[] | undefined>;
		onSave?: () => void;
	}

	let { contactInfo = null, errors, onSave }: Props = $props();

	/** `phone` is a jsonb column, stored as `{ primary: "..." }`. */
	let phone = $derived.by(() => {
		const value = contactInfo?.phone;
		if (value && typeof value === 'object' && 'primary' in value) {
			const primary = (value as { primary?: unknown }).primary;
			if (typeof primary === 'string') return primary;
		}
		return '';
	});
</script>

<form
	method="POST"
	action="?/updateContact"
	use:enhance={() => {
		return ({ result, update }) => {
			if (result.type === 'success') onSave?.();
			return update();
		};
	}}
	class="space-y-6"
>
	<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
		<div>
			<label for="email">Email</label>
			<input id="email" type="email" name="email" value={contactInfo?.email ?? ''} />
			{#if errors?.email}<p class="text-sm text-red-600">{errors.email[0]}</p>{/if}
		</div>

		<div>
			<label for="phone">Phone</label>
			<input id="phone" type="tel" name="phone" value={phone} />
		</div>

		<div>
			<label for="website">Website</label>
			<input id="website" type="url" name="website" value={contactInfo?.website ?? ''} />
			{#if errors?.website}<p class="text-sm text-red-600">{errors.website[0]}</p>{/if}
		</div>

		<div>
			<label for="physical_address">Physical Address</label>
			<textarea id="physical_address" name="physical_address" rows="3"
				>{contactInfo?.physical_address ?? ''}</textarea
			>
		</div>

		<div>
			<label for="postal_address">Postal Address</label>
			<textarea id="postal_address" name="postal_address" rows="3"
				>{contactInfo?.postal_address ?? ''}</textarea
			>
		</div>
	</div>

	<div class="flex justify-end">
		<button class="btn preset-filled" type="submit">Save Changes</button>
	</div>
</form>
