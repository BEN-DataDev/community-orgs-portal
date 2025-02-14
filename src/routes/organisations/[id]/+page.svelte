<script lang="ts">
	import OrganisationForm from '$components/forms/OrganisationForm.svelte';
	import RelationshipsTable from '$components/tables/RelationshipsTable.svelte';

	let { data } = $props();

	let { organisation, relationships } = $derived(data);
	let isEditing = $state(false);
</script>

<div class="container mx-auto px-4 py-8">
	<div class="mb-6 flex items-center justify-between">
		<div>
			<h1 class="text-2xl font-bold">{organisation.legal_name}</h1>
			{#if organisation.trading_name}
				<p class="text-gray-600">Trading as: {organisation.trading_name}</p>
			{/if}
		</div>
		<div class="flex gap-4">
			<a href="/organisations/{organisation.org_id}/roles" class="preset-filled-secondary btn">
				Manage Roles
			</a>
			<button onclick={() => (isEditing = !isEditing)}>
				{isEditing ? 'Cancel Edit' : 'Edit Details'}
			</button>
		</div>
	</div>

	<div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
		<div class="lg:col-span-2">
			<OrganisationForm {organisation} {isEditing} />
		</div>

		<div>
			<card title="Relationships">
				<RelationshipsTable relationships={relationships ?? []} />
				<div class="mt-4">
					<a
						href="/organisations/{organisation.org_id}/relationships/new"
						class="preset-filled-secondary btn w-full"
					>
						Add Relationship
					</a>
				</div>
			</card>
		</div>
	</div>
</div>
