<script lang="ts">
	import { enhance } from '$app/forms';
	import OrganisationSearch from '$components/common/OrganisationSearch.svelte';
	import type { SupabaseClient } from '@supabase/supabase-js';

	interface Props {
		orgId: number;
		onSave?: () => void;
		supabase: SupabaseClient;
	}

	let { orgId, onSave, supabase }: Props = $props();

	let selectedPartner: any = $state(null);
	let relationshipType = $state('');
	let startDate = $state('');
	let endDate = $state('');
	let description = $state('');

	const relationshipTypes = [
		'Partnership',
		'Funding',
		'Service Provider',
		'Network Member',
		'Collaboration',
		'Strategic Alliance'
	];
</script>

<form
	method="POST"
	action="?/createRelationship"
	use:enhance={() => {
		return ({ result }: { result: { type: string } }) => {
			if (result.type === 'success') {
				onSave?.();
			}
		};
	}}
	class="space-y-6"
>
	<input type="hidden" name="org_id" value={orgId} />
	<input type="hidden" name="partner_org_id" value={selectedPartner?.org_id} />

	<div>
		<label for="partner-organisation">Partner Organisation</label>
		<OrganisationSearch bind:selected={selectedPartner} id="partner-organisation" {supabase} />
	</div>

	<div>
		<label for="relationship-type">Relationship Type</label>
		<select
			bind:value={relationshipType}
			name="relationship_type"
			required
			class="w-full"
			id="relationship-type"
		>
			<option value="">Select type...</option>
			{#each relationshipTypes as type}
				<option value={type}>{type}</option>
			{/each}
		</select>
	</div>

	<div class="grid grid-cols-2 gap-4">
		<div>
			<label for="start-date">Start Date</label>
			<input type="date" bind:value={startDate} name="start_date" required id="start-date" />
		</div>
		<div>
			<label for="end-date">End Date</label>
			<input type="date" bind:value={endDate} name="end_date" id="end-date" />
		</div>
	</div>

	<div>
		<label for="description">Description</label>
		<textarea bind:value={description} name="description" rows="3" class="w-full" id="description"
		></textarea>
	</div>

	<div class="flex justify-end gap-4">
		<button type="submit" disabled={!selectedPartner}>Create Relationship</button>
	</div>
</form>
