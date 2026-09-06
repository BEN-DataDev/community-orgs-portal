<script lang="ts">
	import OrganisationTable from '$components/tables/OrganisationTable.svelte';
	import Pagination from '$components/common/Pagination.svelte';
	import OrganisationForm from '$components/forms/OrganisationForm.svelte';

	let { data, form } = $props();
	let { organisations, totalCount, currentPage, totalPages } = $derived(data);
	let showCreateForm = $state(false);
</script>

<div>
	<div class="mb-6 flex items-center justify-between">
		<div>
			<h1 class="text-2xl font-bold">Organisations</h1>
			<p class="text-gray-600">Total: {totalCount}</p>
		</div>
		<button class="btn btn-md preset-filled" onclick={() => (showCreateForm = !showCreateForm)}>
			{showCreateForm ? 'Cancel' : 'Add Organisation'}
		</button>
	</div>

	{#if form?.message}
		<p class="mb-4 text-red-600">{form.message}</p>
	{/if}

	{#if showCreateForm}
		<div class="mb-6 rounded-lg border p-4">
			<OrganisationForm
				action="createOrganisation"
				errors={form?.errors}
				onSave={() => (showCreateForm = false)}
			/>
		</div>
	{/if}

	<OrganisationTable organisations={organisations ?? []} />

	<div class="mt-4">
		<Pagination {currentPage} {totalPages} baseUrl="/organisations" />
	</div>
</div>
