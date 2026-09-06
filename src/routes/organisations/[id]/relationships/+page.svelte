<script lang="ts">
	import { page } from '$app/state';
	import RelationshipForm from '$components/forms/RelationshipForm.svelte';
	import RelationshipTimeline from '$components/visualizations/RelationshipTimeline.svelte';
	import { formatDate } from '$lib/utils/formatters';

	let { data, form } = $props();

	let { relationships, organisation, supabase } = $derived(data);
	let showCreateForm = $state(false);
	let active = $derived((relationships ?? []).filter((r) => !r.end_date));
</script>

<div>
	<div class="mb-6 flex items-center justify-between">
		<div>
			<h1 class="text-2xl font-bold">Relationships</h1>
			<p class="text-gray-600">{organisation.entity_name}</p>
		</div>
		<button class="btn preset-filled" onclick={() => (showCreateForm = !showCreateForm)}>
			{showCreateForm ? 'Cancel' : 'Add Relationship'}
		</button>
	</div>

	{#if form?.message}
		<p class="mb-4 text-red-600">{form.message}</p>
	{/if}

	{#if showCreateForm}
		<div class="mb-6 rounded-lg border p-4">
			<RelationshipForm
				orgId={Number(page.params.id)}
				errors={form?.errors}
				onSave={() => (showCreateForm = false)}
				{supabase}
			/>
		</div>
	{/if}

	<div class="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3">
		<div class="lg:col-span-2">
			<RelationshipTimeline relationships={relationships ?? []} />
		</div>

		<div class="rounded-lg border p-4">
			<h2 class="mb-2 font-medium">Active Relationships</h2>
			{#each active as relationship (relationship.relationship_id)}
				<div class="border-b py-3 last:border-0">
					<h3 class="font-medium">{relationship.partner_org ?? '—'}</h3>
					<p class="text-sm text-gray-600">{relationship.relationship_type ?? '—'}</p>
					<p class="text-sm text-gray-500">
						Since {relationship.start_date ? formatDate(relationship.start_date) : '—'}
					</p>
				</div>
			{:else}
				<p class="text-gray-600">No active relationships.</p>
			{/each}
		</div>
	</div>
</div>
