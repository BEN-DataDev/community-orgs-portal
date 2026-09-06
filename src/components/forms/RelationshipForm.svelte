<script lang="ts">
	import { enhance } from '$app/forms';
	import OrganisationSearch from '$components/common/OrganisationSearch.svelte';
	import type { TypedSupabaseClient } from '$lib/supabase-client';
	import type { Database } from '$lib/db.types';

	type Organisation = Database['community_orgs']['Tables']['organisations']['Row'];

	interface Props {
		/** Excluded from the partner search so an organisation cannot partner itself. */
		orgId: number;
		errors?: Record<string, string[] | undefined>;
		onSave?: () => void;
		supabase: TypedSupabaseClient;
	}

	let { orgId, errors, onSave, supabase }: Props = $props();

	/**
	 * `relationships.partner_org` is a text column, not a foreign key, so the
	 * partner is stored by name. Picking from the register keeps those names
	 * consistent with the organisations already on file.
	 */
	let selectedPartner = $state<Organisation | null>(null);
	let partnerName = $derived(selectedPartner?.entity_name ?? '');

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
		return ({ result, update }) => {
			if (result.type === 'success') onSave?.();
			return update();
		};
	}}
	class="space-y-6"
>
	<input class="input" type="hidden" name="partner_org" value={partnerName} />

	<div>
		<label class="label label-text" for="partner-organisation">Partner Organisation</label>
		<OrganisationSearch
			bind:selected={selectedPartner}
			id="partner-organisation"
			excludeIds={[orgId]}
			{supabase}
		/>
		{#if errors?.partner_org}
			<p class="text-error-500 text-sm">{errors.partner_org[0]}</p>
		{/if}
	</div>

	<div>
		<label class="label label-text" for="relationship-type">Relationship Type</label>
		<select name="relationship_type" required class="select w-full" id="relationship-type">
			<option value="">Select type...</option>
			{#each relationshipTypes as type}
				<option value={type}>{type}</option>
			{/each}
		</select>
	</div>

	<div class="grid grid-cols-2 gap-4">
		<div>
			<label class="label label-text" for="start-date">Start Date</label>
			<input class="input" type="date" name="start_date" required id="start-date" />
		</div>
		<div>
			<label class="label label-text" for="end-date">End Date</label>
			<input class="input" type="date" name="end_date" id="end-date" />
		</div>
	</div>

	<div class="flex justify-end gap-4">
		<button class="btn preset-filled" type="submit" disabled={!selectedPartner}>
			Create Relationship
		</button>
	</div>
</form>
