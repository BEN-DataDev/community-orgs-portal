<script lang="ts">
	import { enhance } from '$app/forms';

	interface ContactInfo {
		org_id: string;
		email: string;
		phone: string;
		website?: string;
		street_address: string;
		city: string;
		state: string;
		postal_code: string;
		country: string;
	}

	interface Props {
		contactInfo: ContactInfo;
		onSave?: () => void;
	}

	let { contactInfo, onSave }: Props = $props();
</script>

<form
	method="POST"
	action="?/updateContact"
	use:enhance={() => {
		return ({ result }: { result: { type: string } }) => {
			if (result.type === 'success') {
				onSave?.();
			}
		};
	}}
	class="space-y-6"
>
	<input type="hidden" name="orgId" value={contactInfo.org_id} />

	<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
		<div>
			<label for="email">Email</label>
			<input id="email" type="email" name="email" value={contactInfo.email} required />
		</div>

		<div>
			<label for="phone">Phone</label>
			<input id="phone" type="tel" name="phone" value={contactInfo.phone} required />
		</div>

		<div>
			<label for="website">Website</label>
			<input id="website" type="url" name="website" value={contactInfo.website} />
		</div>

		<div>
			<label for="street_address">Street Address</label>
			<input
				id="street_address"
				type="text"
				name="street_address"
				value={contactInfo.street_address}
				required
			/>
		</div>

		<div>
			<label for="city">City</label>
			<input id="city" type="text" name="city" value={contactInfo.city} required />
		</div>

		<div>
			<label for="state">State</label>
			<input id="state" type="text" name="state" value={contactInfo.state} required />
		</div>

		<div>
			<label for="postal_code">Postal Code</label>
			<input
				id="postal_code"
				type="text"
				name="postal_code"
				value={contactInfo.postal_code}
				required
			/>
		</div>

		<div>
			<label for="country">Country</label>
			<input id="country" type="text" name="country" value={contactInfo.country} required />
		</div>
	</div>

	<div class="flex justify-end">
		<button class="variant-filled btn" type="submit">Save Changes</button>
	</div>
</form>
