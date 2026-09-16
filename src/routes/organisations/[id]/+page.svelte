<script lang="ts">
	import { resolve } from '$app/paths';
	import OrganisationForm from '$components/forms/OrganisationForm.svelte';
	import RelationshipsTable from '$components/tables/RelationshipsTable.svelte';
	import { EDITOR_LEVEL } from '$lib/role-levels';

	let { data, form } = $props();

	let { organisation, relationships, roleLevel } = $derived(data);
	let canEdit = $derived(roleLevel >= EDITOR_LEVEL);
	let isEditing = $state(false);

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
	{#if data.sources.length}
		<section
			aria-label="Sources and freshness"
			class="card preset-outlined-surface-200-800 mt-6 space-y-3 p-4"
		>
			<h2 class="font-semibold">Sources and freshness</h2>
			<p class="text-sm">
				Source observation dates describe when data was retrieved, not when the organisation last
				confirmed it.
			</p>
			<ul class="space-y-3">
				{#each data.sources as source}<li>
						<p>
							<strong
								>{source.field === 'entity_name'
									? 'Entity name'
									: source.field === 'abn'
										? 'ABN'
										: source.field === 'website'
											? 'Website'
											: source.field}</strong
							>
							· {#if source.url}<a class="anchor" href={source.url} rel="noopener noreferrer"
									>{source.title}</a
								>{:else}{source.title}{/if}
						</p>
						<p class="text-sm">
							Source observed: {new Date(source.observed_at).toLocaleDateString('en-AU', {
								timeZone: 'UTC'
							})} · Published: {new Date(source.published_at).toLocaleDateString('en-AU', {
								timeZone: 'UTC'
							})}
						</p>
						<p class="text-sm">
							{source.unchanged_since_import
								? 'Unchanged since import; not independently verified.'
								: 'Edited since import; the current value may differ from this source.'}
						</p>
						{#if source.licence}<p class="text-sm">
								Licence: {#if source.licence_url}<a
										class="anchor"
										href={source.licence_url}
										rel="noopener noreferrer">{source.licence}</a
									>{:else}{source.licence}{/if}
							</p>{/if}
					</li>{/each}
			</ul>
		</section>
	{/if}
</div>
