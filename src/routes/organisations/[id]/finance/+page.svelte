<script lang="ts">
	import FinancialForm from '$components/forms/FinancialForm.svelte';
	import { formatCurrency } from '$lib/utils/formatters';

	let { data } = $props();

	let { financialInfo } = $derived(data);
	let isEditing = $state(false);
</script>

<div class="container mx-auto px-4 py-8">
	<div class="mb-6 flex items-center justify-between">
		<div>
			<h1 class="text-2xl font-bold">Financial Information</h1>
			<p class="text-gray-600">{financialInfo.organisations.legal_name}</p>
		</div>
		<button class="variant-filled btn" onclick={() => (isEditing = !isEditing)}>
			{isEditing ? 'Cancel' : 'Edit Financial Info'}
		</button>
	</div>

	{#if isEditing}
		<FinancialForm {financialInfo} onSave={() => (isEditing = false)} />
	{:else}
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
			<card title="Annual Revenue">
				<div class="text-2xl font-bold">
					{formatCurrency(financialInfo.annual_revenue)}
				</div>
				<p class="text-sm text-gray-600">
					Financial Year: {financialInfo.financial_year}
				</p>
			</card>

			<card title="Funding Sources">
				<div class="space-y-2">
					{#each financialInfo.funding_sources as source}
						<div class="flex justify-between">
							<span>{source.name}</span>
							<span>{source.percentage}%</span>
						</div>
					{/each}
				</div>
			</card>

			<card title="Financial Status">
				<div class="space-y-2">
					<p><strong>Tax Status:</strong> {financialInfo.tax_status}</p>
					<p><strong>DGR Status:</strong> {financialInfo.dgr_status ? 'Yes' : 'No'}</p>
					<p>
						<strong>Last Audit:</strong>
						{new Date(financialInfo.last_audit_date).toLocaleDateString()}
					</p>
				</div>
			</card>
		</div>
	{/if}
</div>
