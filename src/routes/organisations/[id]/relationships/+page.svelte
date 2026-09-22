<script lang="ts">
	import RelationshipForm from '$components/forms/RelationshipForm.svelte';
	import RelationshipTimeline from '$components/visualizations/RelationshipTimeline.svelte';
	import { formatDate } from '$lib/utils/formatters';
	import { EDITOR_LEVEL } from '$lib/role-levels';

	let { data, form } = $props();

	let { relationships, organisation, supabase, roleLevel } = $derived(data);
	let canEdit = $derived(roleLevel >= EDITOR_LEVEL);
	let showCreateForm = $state(false);
	let editingRelationshipId = $state<string | null>(null);
	let active = $derived((relationships ?? []).filter((r) => !r.end_date));
</script>

<div>
	<div class="mb-6 flex flex-wrap items-start justify-between gap-3">
		<div>
			<h1 class="text-2xl font-bold">Relationships</h1>
			<p class="text-surface-600-400">{organisation.entity_name}</p>
		</div>
		{#if canEdit}
			<button class="btn preset-filled" onclick={() => (showCreateForm = !showCreateForm)}>
				{showCreateForm ? 'Cancel' : 'Add Relationship'}
			</button>
		{/if}
	</div>

	{#if form?.message}
		<p class="text-error-500 mb-4">{form.message}</p>
	{/if}

	{#if showCreateForm && canEdit}
		<div class="card preset-outlined-surface-200-800 mb-6 p-4">
			<RelationshipForm
				orgId={organisation.org_id}
				errors={form?.errors}
				onSave={() => (showCreateForm = false)}
				{supabase}
			/>
		</div>
	{/if}

	<div class="card preset-outlined-surface-200-800 mt-6 space-y-3 p-4">
		<h2 class="font-medium">Relationship records</h2>
		{#each relationships as relationship (relationship.relationship_id)}
			{#if editingRelationshipId === relationship.relationship_id && canEdit}
				<form method="POST" action="?/updateRelationship" class="grid gap-3 md:grid-cols-2">
					<input type="hidden" name="relationship_id" value={relationship.relationship_id} />
					<label class="label"
						><span class="label-text">Partner organisation</span><input
							class="input"
							name="partner_org"
							value={relationship.partner_org ?? ''}
							required
						/></label
					>
					<label class="label"
						><span class="label-text">Relationship type</span><input
							class="input"
							name="relationship_type"
							value={relationship.relationship_type ?? ''}
							required
						/></label
					>
					<label class="label"
						><span class="label-text">Start date</span><input
							class="input"
							type="date"
							name="start_date"
							value={relationship.start_date ?? ''}
							required
						/></label
					>
					<label class="label"
						><span class="label-text">End date</span><input
							class="input"
							type="date"
							name="end_date"
							value={relationship.end_date ?? ''}
						/></label
					>
					{#if form?.errors?.end_date}
						<p class="text-error-500 text-sm md:col-span-2">{form.errors.end_date[0]}</p>
					{/if}
					<div class="flex gap-2 md:col-span-2">
						<button type="submit" class="btn preset-filled">Save</button>
						<button
							type="button"
							class="btn preset-tonal"
							onclick={() => (editingRelationshipId = null)}>Cancel</button
						>
					</div>
				</form>
			{:else}
				<div
					class="border-surface-200-800 flex items-start justify-between gap-3 border-b pb-3 last:border-0"
				>
					<div>
						<p class="font-medium">{relationship.partner_org ?? '—'}</p>
						<p class="text-surface-600-400 text-sm">
							{relationship.relationship_type ?? '—'} · {relationship.start_date
								? formatDate(relationship.start_date)
								: '—'} – {relationship.end_date ? formatDate(relationship.end_date) : 'Current'}
						</p>
					</div>
					{#if canEdit}
						<button
							type="button"
							class="btn btn-sm preset-tonal"
							onclick={() => (editingRelationshipId = relationship.relationship_id)}>Edit</button
						>
					{/if}
				</div>
			{/if}
		{:else}
			<p class="text-surface-600-400">No relationships recorded.</p>
		{/each}
	</div>

	<div class="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3">
		<div class="lg:col-span-2">
			<RelationshipTimeline relationships={relationships ?? []} />
		</div>

		<div class="card preset-outlined-surface-200-800 p-4">
			<h2 class="mb-2 font-medium">Active Relationships</h2>
			{#each active as relationship (relationship.relationship_id)}
				<div class="border-surface-200-800 border-b py-3 last:border-0">
					<h3 class="font-medium">{relationship.partner_org ?? '—'}</h3>
					<p class="text-surface-600-400 text-sm">{relationship.relationship_type ?? '—'}</p>
					<p class="text-surface-600-400 text-sm">
						Since {relationship.start_date ? formatDate(relationship.start_date) : '—'}
					</p>
				</div>
			{:else}
				<p class="text-surface-600-400">No active relationships.</p>
			{/each}
		</div>
	</div>
</div>
