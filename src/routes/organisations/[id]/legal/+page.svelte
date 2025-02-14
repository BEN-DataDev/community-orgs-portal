<script lang="ts">
	import LegalForm from '$components/forms/LegalForm.svelte';

	let { data } = $props();

	let { legalInfo } = $derived(data);
	let isEditing = $state(false);
</script>

<div class="container mx-auto px-4 py-8">
	<div class="mb-6 flex items-center justify-between">
		<div>
			<h1 class="text-2xl font-bold">Legal Information</h1>
			<p class="text-gray-600">{legalInfo.organisations.legal_name}</p>
		</div>
		<button class="variant-filled btn" onclick={() => (isEditing = !isEditing)}>
			{isEditing ? 'Cancel' : 'Edit Legal Info'}
		</button>
	</div>

	{#if isEditing}
		<LegalForm {legalInfo} onSave={() => (isEditing = false)} />
	{:else}
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
			<card title="Entity Details">
				<div class="space-y-2">
					<p><strong>Entity Type:</strong> {legalInfo.entity_type}</p>
					<p><strong>ABN:</strong> {legalInfo.abn}</p>
					<p><strong>ACN:</strong> {legalInfo.acn}</p>
					<p>
						<strong>Registration Date:</strong>
						{new Date(legalInfo.registration_date).toLocaleDateString()}
					</p>
				</div>
			</card>

			<card title="Compliance">
				<div class="space-y-2">
					<p><strong>Tax Status:</strong> {legalInfo.tax_status}</p>
					<p><strong>Charity Status:</strong> {legalInfo.charity_status}</p>
					<p>
						<strong>Last Annual Return:</strong>
						{new Date(legalInfo.last_annual_return_date).toLocaleDateString()}
					</p>
				</div>
			</card>

			<card title="Documents">
				<div class="space-y-2">
					{#each legalInfo.documents as doc}
						<div class="flex items-center justify-between">
							<span>{doc.name}</span>
							<a href={doc.url} class="text-indigo-600 hover:text-indigo-900"> Download </a>
						</div>
					{/each}
				</div>
			</card>
		</div>
	{/if}
</div>
