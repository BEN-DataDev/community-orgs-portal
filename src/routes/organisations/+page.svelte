<script lang="ts">
	import OrganisationTable from '$components/tables/OrganisationTable.svelte';
	import Pagination from '$components/common/Pagination.svelte';
	import OrganisationForm from '$components/forms/OrganisationForm.svelte';

	let { data } = $props();
	let { organisations, totalCount, currentPage, totalPages } = $derived(data);
	let showCreateForm = $state(false);
</script>

<div class="container mx-auto px-4 py-8">
	<div class="mb-6 flex items-center justify-between">
		<div>
			<h1 class="text-2xl font-bold">Organisations</h1>
			<p class="text-gray-600">Total: {totalCount}</p>
		</div>
		<button class="btn btn-md preset-filled" onclick={() => (showCreateForm = true)}>
			Add Organisation
		</button>
	</div>

	{#if showCreateForm}
		<card class="mb-6">
			<OrganisationForm onSave={() => (showCreateForm = false)} />
		</card>
	{/if}

	<OrganisationTable organisations={organisations ?? []} />

	<div class="mt-4">
		<Pagination {currentPage} {totalPages} baseUrl="/organisations" />
	</div>
</div>
