<script lang="ts">
	import RegisterFacts from '$components/organisations/RegisterFacts.svelte';
	import { resolve } from '$app/paths';
	import OrganisationForm from '$components/forms/OrganisationForm.svelte';
	import RelationshipsTable from '$components/tables/RelationshipsTable.svelte';
	import { EDITOR_LEVEL } from '$lib/role-levels';

	let { data, form } = $props();

	let { organisation, relationships, roleLevel } = $derived(data);
	let canEdit = $derived(roleLevel >= EDITOR_LEVEL);
	let isEditing = $state(false);
	let editingAliasId = $state<string | null>(null);

	let tradingNames = $derived(
		(organisation.aliases ?? []).filter((alias) => alias.alias_type === 'Trading Name')
	);
</script>

<div>
	<div class="mb-6 flex flex-wrap items-start justify-between gap-3">
		<div>
			<h1 class="text-2xl font-bold">{organisation.entity_name}</h1>
			{#each tradingNames as alias}
				<p class="text-surface-600-400">Trading as: {alias.alias}</p>
			{/each}
			{#if !organisation.is_public}
				<p class="text-surface-600-400 text-sm">Private — visible to members only</p>
			{/if}
		</div>
		{#if canEdit}
			<button class="btn preset-filled" onclick={() => (isEditing = !isEditing)}>
				{isEditing ? 'Cancel Edit' : 'Edit Details'}
			</button>
		{/if}
	</div>

	{#if form?.message}
		<p class="text-error-500 mb-4">{form.message}</p>
	{/if}

	<div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
		<div class="lg:col-span-2">
			{#if isEditing && canEdit}
				<OrganisationForm
					{organisation}
					action="updateOrganisation"
					errors={form?.errors}
					onSave={() => (isEditing = false)}
				/>
			{:else}
				<div class="card preset-outlined-surface-200-800 space-y-2 p-4">
					<div><span class="font-medium">Entity name:</span> {organisation.entity_name}</div>
					<div><span class="font-medium">Slug:</span> {organisation.slug}</div>
					<div>
						<span class="font-medium">Established:</span>
						{organisation.date_established ?? '—'}
					</div>
					<div><span class="font-medium">Description:</span> {organisation.description ?? '—'}</div>
				</div>
			{/if}

			<div class="card preset-outlined-surface-200-800 mt-4 space-y-3 p-4">
				<h2 class="font-medium">Business and trading names</h2>
				{#each organisation.aliases ?? [] as alias (alias.alias_id)}
					{#if editingAliasId === alias.alias_id && canEdit}
						<form
							method="POST"
							action="?/updateAlias"
							class="grid gap-3 sm:grid-cols-[1fr_auto_auto] sm:items-end"
						>
							<input type="hidden" name="alias_id" value={alias.alias_id} />
							<div>
								<label class="label label-text" for={`alias-${alias.alias_id}`}>Name</label>
								<input
									class="input"
									id={`alias-${alias.alias_id}`}
									name="alias"
									value={alias.alias ?? ''}
									required
								/>
							</div>
							<div>
								<label class="label label-text" for={`alias-type-${alias.alias_id}`}>Type</label>
								<select
									class="select"
									id={`alias-type-${alias.alias_id}`}
									name="alias_type"
									value={alias.alias_type ?? 'Trading Name'}
								>
									<option value="Trading Name">Trading Name</option>
									<option value="Business Name">Business Name</option>
								</select>
							</div>
							<div class="flex gap-2">
								<button type="submit" class="btn preset-filled">Save</button>
								<button
									type="button"
									class="btn preset-tonal"
									onclick={() => (editingAliasId = null)}>Cancel</button
								>
							</div>
						</form>
					{:else}
						<div
							class="border-surface-200-800 flex items-center justify-between gap-3 border-b pb-2 last:border-0"
						>
							<div>
								<p>{alias.alias ?? '—'}</p>
								<p class="text-surface-600-400 text-sm">{alias.alias_type ?? 'Name'}</p>
							</div>
							{#if canEdit}
								<button
									type="button"
									class="btn btn-sm preset-tonal"
									onclick={() => (editingAliasId = alias.alias_id)}>Edit</button
								>
							{/if}
						</div>
					{/if}
				{:else}
					<p class="text-surface-600-400">No alternate names recorded.</p>
				{/each}
			</div>

			{#if canEdit}
				<form
					method="POST"
					action="?/addAlias"
					class="card preset-outlined-surface-200-800 mt-4 flex flex-wrap items-end gap-3 p-4"
				>
					<div>
						<label class="label label-text" for="alias">Add a business or trading name</label>
						<input class="input" id="alias" name="alias" type="text" required />
					</div>
					<div>
						<label class="label label-text" for="alias_type">Type</label>
						<select class="select" id="alias_type" name="alias_type">
							<option value="Trading Name">Trading Name</option>
							<option value="Business Name">Business Name</option>
						</select>
					</div>
					<button type="submit" class="btn preset-filled">Add</button>
				</form>
			{/if}
		</div>

		<div class="card preset-outlined-surface-200-800 p-4">
			<h2 class="mb-2 font-medium">Relationships</h2>
			<RelationshipsTable relationships={relationships ?? []} />
			<div class="mt-4">
				<a
					href={resolve('/organisations/[id]/relationships', { id: organisation.org_id })}
					class="btn preset-filled-secondary w-full"
				>
					Manage Relationships
				</a>
			</div>
		</div>
	</div>

	<RegisterFacts facts={data.registerFacts} section="Overview" />
	<RegisterFacts facts={data.registerFacts} section="Governance" />
</div>
