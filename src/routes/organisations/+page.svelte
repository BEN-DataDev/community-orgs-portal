<script lang="ts">
	import OrganisationTable from '$components/tables/OrganisationTable.svelte';
	import Pagination from '$components/common/Pagination.svelte';
	import OrganisationForm from '$components/forms/OrganisationForm.svelte';

	let { data, form } = $props();
	let { organisations, totalCount, currentPage, totalPages, pageSize } = $derived(data);
	let showCreateForm = $state(false);
</script>

<div>
	<div class="mb-6 flex flex-wrap items-start justify-between gap-3">
		<div>
			<h1 class="text-2xl font-bold">Organisations</h1>
			<p class="text-surface-600-400">Total: {totalCount}</p>
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

	<OrganisationTable organisations={organisations ?? []} />

	<div class="mt-4">
		<Pagination {currentPage} {totalPages} {totalCount} {pageSize} baseUrl="/organisations" />
	</div>
</div>
