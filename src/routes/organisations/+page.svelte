<script lang="ts">
	import { resolve } from '$app/paths';
	import OrganisationTable from '$components/tables/OrganisationTable.svelte';
	import Pagination from '$components/common/Pagination.svelte';
	import OrganisationForm from '$components/forms/OrganisationForm.svelte';

	let { data, form } = $props();
	let { organisations, totalCount, currentPage, totalPages, pageSize, searchQuery } =
		$derived(data);
	let showCreateForm = $state(false);
</script>

<div>
	<div class="mb-6 flex flex-wrap items-start justify-between gap-3">
		<div>
			<h1 class="text-2xl font-bold">Organisations</h1>
			<p class="text-surface-600-400">{searchQuery ? 'Matching' : 'Total'}: {totalCount}</p>
		</div>
		<button class="btn btn-md preset-filled" onclick={() => (showCreateForm = !showCreateForm)}>
			{showCreateForm ? 'Cancel' : 'Add Organisation'}
		</button>
	</div>

	{#if form?.message}
		<p class="text-error-500 mb-4">{form.message}</p>
	{/if}

	{#if showCreateForm}
		<div class="card preset-outlined-surface-200-800 mb-6 p-4">
			<OrganisationForm
				action="createOrganisation"
				errors={form?.errors}
				onSave={() => (showCreateForm = false)}
			/>
		</div>
	{/if}

	<form
		method="GET"
		class="card preset-outlined-surface-200-800 mb-6 flex flex-wrap items-end gap-3 p-4"
	>
		<div class="min-w-64 flex-1">
			<label class="label label-text" for="directory-search">Search the directory</label>
			<input
				class="input"
				id="directory-search"
				name="q"
				type="search"
				value={searchQuery}
				placeholder="Organisation name, alias, or exact ABN"
				maxlength="100"
			/>
		</div>
		<button type="submit" class="btn preset-filled">Search</button>
		{#if searchQuery}
			<a class="btn preset-tonal" href={resolve('/organisations')}>Clear</a>
		{/if}
	</form>

	{#if searchQuery}
		<p class="text-surface-600-400 mb-3 text-sm">
			{totalCount}
			{totalCount === 1 ? 'result' : 'results'} for “{searchQuery}”
		</p>
	{/if}

	<OrganisationTable organisations={organisations ?? []} />

	<div class="mt-4">
		<Pagination
			{currentPage}
			{totalPages}
			{totalCount}
			{pageSize}
			baseUrl={resolve('/organisations')}
			query={searchQuery ? { q: searchQuery } : {}}
		/>
	</div>
</div>
