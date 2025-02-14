<script lang="ts">
	import { enhance } from '$app/forms';

	interface Props {
		financialInfo: any;
		onSave?: () => void;
	}

	let { financialInfo, onSave }: Props = $props();

	let fundingSources = $state(financialInfo.funding_sources || []);

	function addFundingSource() {
		fundingSources = [...fundingSources, { name: '', percentage: 0 }];
	}

	function removeFundingSource(index: number) {
		fundingSources = fundingSources.filter((_: any, i: number) => i !== index);
	}
</script>

<form
	method="POST"
	action="?/updateFinancial"
	use:enhance={() => {
		return ({ result }: { result: { type: string } }) => {
			if (result.type === 'success') {
				onSave?.();
			}
		};
	}}
	class="space-y-6"
>
	<input type="hidden" name="orgId" value={financialInfo.org_id} />
	<input type="hidden" name="funding_sources" value={JSON.stringify(fundingSources)} />

	<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
		<div>
			<label for="annual_revenue">Annual Revenue</label>
			<input
				type="number"
				id="annual_revenue"
				name="annual_revenue"
				value={financialInfo.annual_revenue}
				required
			/>
		</div>

		<div>
			<label for="financial_year">Financial Year</label>
			<input
				type="text"
				id="financial_year"
				name="financial_year"
				value={financialInfo.financial_year}
				required
			/>
		</div>

		<div>
			<label for="tax_status">Tax Status</label>
			<select id="tax_status" name="tax_status" value={financialInfo.tax_status} required>
				<option value="For-Profit">For-Profit</option>
				<option value="Non-Profit">Non-Profit</option>
				<option value="Charity">Charity</option>
			</select>
		</div>

		<div>
			<label for="dgr_status">DGR Status</label>
			<select id="dgr_status" name="dgr_status" value={financialInfo.dgr_status}>
				<option value={true}>Yes</option>
				<option value={false}>No</option>
			</select>
		</div>

		<div>
			<label for="last_audit_date">Last Audit Date</label>
			<input
				type="date"
				id="last_audit_date"
				name="last_audit_date"
				value={financialInfo.last_audit_date}
			/>
		</div>
	</div>
	<div>
		<h3 class="mb-2 font-medium">Funding Sources</h3>
		{#each fundingSources as source, index}
			<div class="mb-2 flex gap-4">
				<input type="text" bind:value={source.name} placeholder="Source name" />
				<input type="number" bind:value={source.percentage} min="0" max="100" />
				<button
					type="button"
					class="variant-filled-warning btn"
					onclick={() => removeFundingSource(index)}
				>
					Remove
				</button>
			</div>
		{/each}
		<button type="button" class="variant-filled btn" onclick={addFundingSource}>
			Add Funding Source
		</button>
	</div>

	<div class="flex justify-end">
		<button type="submit">Save Changes</button>
	</div>
</form>
