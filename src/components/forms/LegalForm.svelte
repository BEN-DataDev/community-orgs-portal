<script lang="ts">
	import { enhance } from '$app/forms';
	import type { Database } from '$lib/db.types';

	type LegalDetails = Database['community_orgs']['Tables']['legal_details']['Row'];

	interface Props {
		legalInfo: LegalDetails | null;
		errors?: Record<string, string[] | undefined>;
		onSave?: () => void;
	}

	let { legalInfo = null, errors, onSave }: Props = $props();

	const entityTypes = [
		'Company',
		'Incorporated Association',
		'Trust',
		'Partnership',
		'Unincorporated Association'
	];
	const charityTypes = ['Public Benevolent Institution', 'Health Promotion Charity', 'Other'];
</script>

<form
	method="POST"
	action="?/updateLegal"
	use:enhance={() => {
		return ({ result, update }) => {
			if (result.type === 'success') onSave?.();
			return update();
		};
	}}
	class="space-y-8"
>
	<fieldset class="space-y-4">
		<legend class="font-medium">Entity</legend>
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
			<div>
				<label for="entity_type">Entity Type</label>
				<select id="entity_type" name="entity_type">
					<option value="">Not recorded</option>
					{#each entityTypes as type}
						<option value={type} selected={legalInfo?.entity_type === type}>{type}</option>
					{/each}
				</select>
			</div>

			<div>
				<label for="charity_type">Charity Type</label>
				<select id="charity_type" name="charity_type">
					<option value="">Not recorded</option>
					{#each charityTypes as type}
						<option value={type} selected={legalInfo?.charity_type === type}>{type}</option>
					{/each}
				</select>
			</div>
		</div>
	</fieldset>

	<fieldset class="space-y-4">
		<legend class="font-medium">ABN &amp; ACN</legend>
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
			<div>
				<label for="abn">ABN</label>
				<input id="abn" type="text" name="abn" value={legalInfo?.abn ?? ''} />
			</div>

			<div class="flex items-center gap-2">
				<input
					id="abn_status"
					type="checkbox"
					name="abn_status"
					checked={legalInfo?.abn_status ?? false}
				/>
				<label for="abn_status">ABN active</label>
			</div>

			<div>
				<label for="abn_activated">ABN Activated</label>
				<input
					id="abn_activated"
					type="date"
					name="abn_activated"
					value={legalInfo?.abn_activated ?? ''}
				/>
			</div>

			<div>
				<label for="abn_last_updated">ABN Last Updated</label>
				<input
					id="abn_last_updated"
					type="date"
					name="abn_last_updated"
					value={legalInfo?.abn_last_updated ?? ''}
				/>
			</div>

			<div>
				<label for="acn">ACN</label>
				<input id="acn" type="text" name="acn" value={legalInfo?.acn ?? ''} />
			</div>
		</div>
	</fieldset>

	<fieldset class="space-y-4">
		<legend class="font-medium">Incorporation</legend>
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
			<div>
				<label for="incorporation_number">Incorporation Number</label>
				<input
					id="incorporation_number"
					type="text"
					name="incorporation_number"
					value={legalInfo?.incorporation_number ?? ''}
				/>
			</div>

			<div class="flex items-center gap-2">
				<input
					id="incorporation_status"
					type="checkbox"
					name="incorporation_status"
					checked={legalInfo?.incorporation_status ?? false}
				/>
				<label for="incorporation_status">Currently incorporated</label>
			</div>

			<div>
				<label for="incorporation_registration_date">Registration Date</label>
				<input
					id="incorporation_registration_date"
					type="date"
					name="incorporation_registration_date"
					value={legalInfo?.incorporation_registration_date ?? ''}
				/>
			</div>
		</div>
	</fieldset>

	<fieldset class="space-y-4">
		<legend class="font-medium">ACNC &amp; Concessions</legend>
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
			<div class="flex items-center gap-2">
				<input
					id="acnc_registered"
					type="checkbox"
					name="acnc_registered"
					checked={legalInfo?.acnc_registered ?? false}
				/>
				<label for="acnc_registered">Registered with the ACNC</label>
			</div>

			<div>
				<label for="acnc_registered_date">ACNC Registration Date</label>
				<input
					id="acnc_registered_date"
					type="date"
					name="acnc_registered_date"
					value={legalInfo?.acnc_registered_date ?? ''}
				/>
			</div>

			<div class="flex items-center gap-2">
				<input
					id="acnc_status"
					type="checkbox"
					name="acnc_status"
					checked={legalInfo?.acnc_status ?? false}
				/>
				<label for="acnc_status">ACNC registration current</label>
			</div>

			<div>
				<label for="last_annual_return_date">Last Annual Return</label>
				<input
					id="last_annual_return_date"
					type="date"
					name="last_annual_return_date"
					value={legalInfo?.last_annual_return_date ?? ''}
				/>
			</div>

			<div class="flex items-center gap-2">
				<input
					id="dgr_endorsement"
					type="checkbox"
					name="dgr_endorsement"
					checked={legalInfo?.dgr_endorsement ?? false}
				/>
				<label for="dgr_endorsement">DGR endorsed</label>
			</div>

			<div>
				<label for="tax_concession_endorsement">Tax Concession Endorsement</label>
				<input
					id="tax_concession_endorsement"
					type="date"
					name="tax_concession_endorsement"
					value={legalInfo?.tax_concession_endorsement ?? ''}
				/>
			</div>

			<div>
				<label for="gst_concession_endorsement_date">GST Concession Endorsement</label>
				<input
					id="gst_concession_endorsement_date"
					type="text"
					name="gst_concession_endorsement_date"
					value={legalInfo?.gst_concession_endorsement_date ?? ''}
				/>
			</div>
		</div>
	</fieldset>

	{#if errors?.abn}<p class="text-sm text-red-600">{errors.abn[0]}</p>{/if}

	<div class="flex justify-end">
		<button class="btn preset-filled" type="submit">Save Changes</button>
	</div>
</form>
