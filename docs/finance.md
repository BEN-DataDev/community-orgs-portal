/src/routes/organisations/[id]/finance/+page.server.ts

```ts
import { supabase } from '$lib/services/supabase';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ params }) => {
	const { data: financialInfo } = await supabase
		.from('financial_info')
		.select(
			`
            *,
            organizations (
                legal_name,
                trading_name
            )
        `
		)
		.eq('org_id', params.id)
		.single();

	return { financialInfo };
};

export const actions: Actions = {
	updateFinancial: async ({ request }) => {
		const formData = await request.formData();
		const { orgId, ...financialData } = Object.fromEntries(formData);

		const { data, error } = await supabase
			.from('financial_info')
			.upsert({
				org_id: orgId,
				...financialData
			})
			.select();

		return { success: !error, data };
	}
};
```

/src/routes/organisations/[id]/finance/+page.svelte

```svelte
<script lang="ts">
	import { enhance } from '$app/forms';
	import { Button, Card } from '$lib/components/common';
	import FinancialForm from '$lib/components/forms/FinancialForm.svelte';
	import { formatCurrency } from '$lib/utils/formatters';

	let { data } = $props();

	let { financialInfo } = $derived(data);
	let isEditing = $state(false);
</script>

<div class="container mx-auto px-4 py-8">
	<div class="mb-6 flex items-center justify-between">
		<div>
			<h1 class="text-2xl font-bold">Financial Information</h1>
			<p class="text-gray-600">{financialInfo.organizations.legal_name}</p>
		</div>
		<Button on:click={() => (isEditing = !isEditing)}>
			{isEditing ? 'Cancel' : 'Edit Financial Info'}
		</Button>
	</div>

	{#if isEditing}
		<FinancialForm {financialInfo} on:save={() => (isEditing = false)} />
	{:else}
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
			<Card title="Annual Revenue">
				<div class="text-2xl font-bold">
					{formatCurrency(financialInfo.annual_revenue)}
				</div>
				<p class="text-sm text-gray-600">
					Financial Year: {financialInfo.financial_year}
				</p>
			</Card>

			<Card title="Funding Sources">
				<div class="space-y-2">
					{#each financialInfo.funding_sources as source}
						<div class="flex justify-between">
							<span>{source.name}</span>
							<span>{source.percentage}%</span>
						</div>
					{/each}
				</div>
			</Card>

			<Card title="Financial Status">
				<div class="space-y-2">
					<p><strong>Tax Status:</strong> {financialInfo.tax_status}</p>
					<p><strong>DGR Status:</strong> {financialInfo.dgr_status ? 'Yes' : 'No'}</p>
					<p>
						<strong>Last Audit:</strong>
						{new Date(financialInfo.last_audit_date).toLocaleDateString()}
					</p>
				</div>
			</Card>
		</div>
	{/if}
</div>
```

FinancialForm.svelte

```svelte
<script lang="ts">
	import { enhance } from '$app/forms';
	import { Button } from '$lib/components/common';

	interface Props {
		financialInfo: any;
	}

	let { financialInfo }: Props = $props();

	let fundingSources = $state(financialInfo.funding_sources || []);

	function addFundingSource() {
		fundingSources = [...fundingSources, { name: '', percentage: 0 }];
	}

	function removeFundingSource(index: number) {
		fundingSources = fundingSources.filter((_, i) => i !== index);
	}
</script>

<form method="POST" action="?/updateFinancial" use:enhance class="space-y-6">
	<input type="hidden" name="orgId" value={financialInfo.org_id} />
	<input type="hidden" name="funding_sources" value={JSON.stringify(fundingSources)} />

	<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
		<div>
			<label>Annual Revenue</label>
			<input type="number" name="annual_revenue" value={financialInfo.annual_revenue} required />
		</div>

		<div>
			<label>Financial Year</label>
			<input type="text" name="financial_year" value={financialInfo.financial_year} required />
		</div>

		<div>
			<label>Tax Status</label>
			<select name="tax_status" value={financialInfo.tax_status} required>
				<option value="For-Profit">For-Profit</option>
				<option value="Non-Profit">Non-Profit</option>
				<option value="Charity">Charity</option>
			</select>
		</div>

		<div>
			<label>DGR Status</label>
			<select name="dgr_status" value={financialInfo.dgr_status}>
				<option value={true}>Yes</option>
				<option value={false}>No</option>
			</select>
		</div>

		<div>
			<label>Last Audit Date</label>
			<input type="date" name="last_audit_date" value={financialInfo.last_audit_date} />
		</div>
	</div>

	<div>
		<h3 class="mb-2 font-medium">Funding Sources</h3>
		{#each fundingSources as source, index}
			<div class="mb-2 flex gap-4">
				<input type="text" bind:value={source.name} placeholder="Source name" />
				<input type="number" bind:value={source.percentage} min="0" max="100" />
				<Button type="button" variant="danger" on:click={() => removeFundingSource(index)}>
					Remove
				</Button>
			</div>
		{/each}
		<Button type="button" on:click={addFundingSource}>Add Funding Source</Button>
	</div>

	<div class="flex justify-end">
		<Button type="submit">Save Changes</Button>
	</div>
</form>
```
