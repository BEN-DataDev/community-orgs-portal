<script lang="ts">
	import { page } from '$app/stores';
	import RelationshipForm from '$components/forms/RelationshipForm.svelte';
	import RelationshipTimeline from '$components/visualizations/RelationshipTimeline.svelte';

	let { data } = $props();

	let { relationships, organisation, supabase } = $derived(data);
	let showCreateForm = $state(false);
</script>

<div class="container mx-auto px-4 py-8">
	<div class="mb-6 flex items-center justify-between">
		<div>
			<h1 class="text-2xl font-bold">Relationships</h1>
			<p class="text-gray-600">{organisation?.legal_name}</p>
		</div>
		<button onclick={() => (showCreateForm = !showCreateForm)}>
			{showCreateForm ? 'Cancel' : 'Add Relationship'}
		</button>
	</div>

	{#if showCreateForm}
		<card>
			<RelationshipForm
				orgId={parseInt($page.params.id)}
				onSave={() => (showCreateForm = false)}
				{supabase}
			/>
		</card>
	{/if}

	<div class="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3">
		<div class="lg:col-span-2">
			<RelationshipTimeline relationships={relationships || []} />
		</div>

		<div>
			<card title="Active Relationships">
				{#each (relationships || []).filter((r) => !r.end_date) as relationship}
					<div class="border-b p-4 last:border-0">
						<h3 class="font-medium">
							{relationship.partner_details.legal_name}
						</h3>
						<p class="text-sm text-gray-600">
							{relationship.relationship_type}
						</p>
						<p class="text-sm text-gray-500">
							Since {new Date(relationship.start_date).toLocaleDateString()}
						</p>
					</div>
				{/each}
			</card>
		</div>
	</div>
</div>
