<script lang="ts">
	import { enhance } from '$app/forms';
	import type { Database } from '$lib/db.types';

	type FinancialInfo = Database['community_orgs']['Tables']['financial_info']['Row'];

	interface Props {
		financialInfo: FinancialInfo | null;
		errors?: Record<string, string[] | undefined>;
		onSave?: () => void;
	}

	let { financialInfo = null, errors, onSave }: Props = $props();
</script>

<form
	method="POST"
	action="?/updateFinancial"
	use:enhance={() => {
		return ({ result, update }) => {
			if (result.type === 'success') onSave?.();
			return update();
		};
	}}
	class="space-y-6"
>
	<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
		<div>
			<label for="annual_budget">Annual Budget (AUD)</label>
			<input
				type="number"
				step="0.01"
				min="0"
				id="annual_budget"
				name="annual_budget"
				value={financialInfo?.annual_budget ?? ''}
			/>
			{#if errors?.annual_budget}
				<p class="text-sm text-red-600">{errors.annual_budget[0]}</p>
			{/if}
		</div>

		<div>
			<label for="financial_year_end">Financial Year End</label>
			<input
				type="date"
				id="financial_year_end"
				name="financial_year_end"
				value={financialInfo?.financial_year_end ?? ''}
			/>
		</div>

		<div>
			<label for="last_audit_date">Last Audit Date</label>
			<input
				type="date"
				id="last_audit_date"
				name="last_audit_date"
				value={financialInfo?.last_audit_date ?? ''}
			/>
		</div>

		<div class="md:col-span-2">
			<label for="funding_sources">Funding Sources</label>
			<input
				type="text"
				id="funding_sources"
				name="funding_sources"
				placeholder="Comma-separated, e.g. Grants, Donations, Membership fees"
				value={(financialInfo?.funding_sources ?? []).join(', ')}
			/>
		</div>
	</div>

	<div class="flex justify-end">
		<button class="btn preset-filled" type="submit">Save Changes</button>
	</div>
</form>
