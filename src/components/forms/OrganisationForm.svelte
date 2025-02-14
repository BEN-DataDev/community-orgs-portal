<script lang="ts">
	import { enhance } from '$app/forms';
	import type { Database } from '$lib/db.types';

	type Organisation = Database['community_orgs']['Tables']['organisations']['Row'];

	interface Props {
		organisation?: Organisation;
		onSave?: () => void;
	}

	let { organisation, onSave }: Props = $props();

	let legalName = $state(organisation?.legal_name || '');
	let tradingName = $state(organisation?.trading_name || '');
	let dateEstablished = $state(organisation?.date_established || '');
</script>

<form
	method="POST"
	action="?/upsertOrganisation"
	use:enhance={() => {
		return ({ result }) => {
			if (result.type === 'success') {
				onSave?.();
			}
		};
	}}
	class="space-y-6"
>
	{#if organisation}
		<input type="hidden" name="org_id" value={organisation.org_id} />
	{/if}

	<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
		<div>
			<label for="legal_name">Legal Name</label>
			<input
				type="text"
				id="legal_name"
				name="legal_name"
				bind:value={legalName}
				required
				class="w-full"
			/>
		</div>

		<div>
			<label for="trading_name">Trading Name</label>
			<input
				type="text"
				id="trading_name"
				name="trading_name"
				bind:value={tradingName}
				class="w-full"
			/>
		</div>

		<div>
			<label for="date_established">Date Established</label>
			<input
				type="date"
				id="date_established"
				name="date_established"
				bind:value={dateEstablished}
				class="w-full"
			/>
		</div>
	</div>

	<div class="flex justify-end gap-4">
		<button type="submit" class="variant-filled btn">
			{organisation ? 'Update' : 'Create'} Organisation
		</button>
	</div>
</form>
