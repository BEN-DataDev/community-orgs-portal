<script lang="ts">
	import FinancialForm from '$components/forms/FinancialForm.svelte';
	import { formatCurrency, formatDate } from '$lib/utils/formatters';
	import { EDITOR_LEVEL } from '$lib/role-levels';

	let { data, form } = $props();
	let { financialInfo, organisation, roleLevel } = $derived(data);
	let canEdit = $derived(roleLevel >= EDITOR_LEVEL);
	let isEditing = $state(false);
</script>

<div>
	<div class="mb-6 flex flex-wrap items-start justify-between gap-3">
		<div>
			<h1 class="text-2xl font-bold">Financial Information</h1>
			<p class="text-surface-600-400">{organisation.entity_name}</p>
		</div>
		{#if canEdit}
			<button class="btn preset-filled" onclick={() => (isEditing = !isEditing)}>
				{isEditing ? 'Cancel' : 'Edit Financial Info'}
			</button>
		{/if}
	</div>

	{#if form?.message}
		<p class="text-error-500 mb-4">{form.message}</p>
	{/if}

	{#if isEditing && canEdit}
		<FinancialForm {financialInfo} errors={form?.errors} onSave={() => (isEditing = false)} />
	{:else if financialInfo}
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2 xl:gap-8">
			<div class="card preset-outlined-surface-200-800 space-y-2 p-4">
				<h2 class="font-medium">Annual Budget</h2>
				<div class="text-2xl font-bold">
					{financialInfo.annual_budget === null ? '—' : formatCurrency(financialInfo.annual_budget)}
				</div>
				<p class="text-surface-600-400 text-sm">
					Financial year end: {financialInfo.financial_year_end
						? formatDate(financialInfo.financial_year_end)
						: '—'}
				</p>
				<p class="text-surface-600-400 text-sm">
					Last audit: {financialInfo.last_audit_date
						? formatDate(financialInfo.last_audit_date)
						: '—'}
				</p>
			</div>

			<div class="card preset-outlined-surface-200-800 space-y-2 p-4">
				<h2 class="font-medium">Funding Sources</h2>
				{#each financialInfo.funding_sources ?? [] as source}
					<div>{source}</div>
				{:else}
					<p class="text-surface-600-400">None recorded.</p>
				{/each}
			</div>
		</div>
	{:else}
		<p class="text-surface-600-400">No financial details recorded yet.</p>
	{/if}
</div>
