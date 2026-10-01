<script lang="ts">
	import { enhance } from '$app/forms';
	import type { Database } from '$lib/db.types';
	import { formatDate } from '$lib/utils/formatters';

	type LegalDetails = Database['community_orgs']['Tables']['legal_details']['Row'];

	interface Props {
		legalInfo: LegalDetails | null;
		errors?: Record<string, string[] | undefined>;
		onSave?: () => void;
		/** Columns supplied by a public register; shown read-only and not submitted. */
		registerSourcedFields?: string[];
	}

	let { legalInfo = null, errors, onSave, registerSourcedFields = [] }: Props = $props();

	const locked = (field: string) => registerSourcedFields.includes(field);
	const dateOrNull = (value: string | null | undefined) => (value ? formatDate(value) : null);
	const statusText = (value: boolean | null | undefined, yes: string, no: string) =>
		value == null ? null : value ? yes : no;

	const entityTypes = [
		'Company',
		'Incorporated Association',
		'Trust',
		'Partnership',
		'Unincorporated Association'
	];
</script>

{#snippet fromRegister(label: string, value: string | null | undefined)}
	<div>
		<span class="label label-text">{label}</span>
		<p class="py-2">{value || 'Not recorded'}</p>
	</div>
{/snippet}

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
	{#if registerSourcedFields.length}
		<p class="text-surface-600-400 text-sm">
			Details supplied by a public register (ABR, ACNC or the NSW Incorporated Associations
			Register) are shown as text and can't be edited here.
		</p>
	{/if}

	<fieldset class="space-y-4">
		<legend class="font-medium">Entity</legend>
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
			{#if locked('entity_type')}
				{@render fromRegister('Entity Type', legalInfo?.entity_type)}
			{:else}
				<div>
					<label class="label label-text" for="entity_type">Entity Type</label>
					<select class="select" id="entity_type" name="entity_type">
						<option value="">Not recorded</option>
						{#each entityTypes as type (type)}
							<option value={type} selected={legalInfo?.entity_type === type}>{type}</option>
						{/each}
					</select>
				</div>
			{/if}

			<p class="text-surface-600-400 text-sm md:self-end">
				Charity subtypes come from the ACNC Charity Register and are listed on the Operations tab.
			</p>
		</div>
	</fieldset>

	<fieldset class="space-y-4">
		<legend class="font-medium">ABN &amp; ACN</legend>
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
			{#if locked('abn')}
				{@render fromRegister('ABN', legalInfo?.abn)}
			{:else}
				<div>
					<label class="label label-text" for="abn">ABN</label>
					<input class="input" id="abn" type="text" name="abn" value={legalInfo?.abn ?? ''} />
				</div>
			{/if}

			{#if locked('abn_status')}
				{@render fromRegister(
					'ABN Status',
					statusText(legalInfo?.abn_status, 'Active', 'Cancelled')
				)}
			{:else}
				<div>
					<label class="label label-text" for="abn_status">ABN Status</label>
					<!-- Three states: a checkbox cannot record "Cancelled" apart from "not recorded". -->
					<select class="select" id="abn_status" name="abn_status">
						<option value="" selected={legalInfo?.abn_status == null}>Not recorded</option>
						<option value="true" selected={legalInfo?.abn_status === true}>Active</option>
						<option value="false" selected={legalInfo?.abn_status === false}>Cancelled</option>
					</select>
				</div>
			{/if}

			{#if locked('abn_activated')}
				{@render fromRegister('ABN Activated', dateOrNull(legalInfo?.abn_activated))}
			{:else}
				<div>
					<label class="label label-text" for="abn_activated">ABN Activated</label>
					<input
						class="input"
						id="abn_activated"
						type="date"
						name="abn_activated"
						value={legalInfo?.abn_activated ?? ''}
					/>
				</div>
			{/if}

			{#if locked('abn_last_updated')}
				{@render fromRegister('ABN Last Updated', dateOrNull(legalInfo?.abn_last_updated))}
			{:else}
				<div>
					<label class="label label-text" for="abn_last_updated">ABN Last Updated</label>
					<input
						class="input"
						id="abn_last_updated"
						type="date"
						name="abn_last_updated"
						value={legalInfo?.abn_last_updated ?? ''}
					/>
				</div>
			{/if}

			<div>
				<label class="label label-text" for="acn">ACN</label>
				<input class="input" id="acn" type="text" name="acn" value={legalInfo?.acn ?? ''} />
			</div>
		</div>
	</fieldset>

	<fieldset class="space-y-4">
		<legend class="font-medium">Incorporation</legend>
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
			{#if locked('incorporation_number')}
				{@render fromRegister('Incorporation Number', legalInfo?.incorporation_number)}
			{:else}
				<div>
					<label class="label label-text" for="incorporation_number">Incorporation Number</label>
					<input
						class="input"
						id="incorporation_number"
						type="text"
						name="incorporation_number"
						value={legalInfo?.incorporation_number ?? ''}
					/>
				</div>
			{/if}

			{#if locked('incorporation_status')}
				{@render fromRegister(
					'Currently incorporated',
					statusText(legalInfo?.incorporation_status, 'Yes', 'No')
				)}
			{:else}
				<div class="flex items-center gap-2">
					<input
						class="checkbox"
						id="incorporation_status"
						type="checkbox"
						name="incorporation_status"
						checked={legalInfo?.incorporation_status ?? false}
					/>
					<label class="label-text" for="incorporation_status">Currently incorporated</label>
				</div>
			{/if}

			{#if locked('incorporation_registration_date')}
				{@render fromRegister(
					'Registration Date',
					dateOrNull(legalInfo?.incorporation_registration_date)
				)}
			{:else}
				<div>
					<label class="label label-text" for="incorporation_registration_date"
						>Registration Date</label
					>
					<input
						class="input"
						id="incorporation_registration_date"
						type="date"
						name="incorporation_registration_date"
						value={legalInfo?.incorporation_registration_date ?? ''}
					/>
				</div>
			{/if}
		</div>
	</fieldset>

	<fieldset class="space-y-4">
		<legend class="font-medium">ACNC &amp; Concessions</legend>
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
			<div class="flex items-center gap-2">
				<input
					class="checkbox"
					id="acnc_registered"
					type="checkbox"
					name="acnc_registered"
					checked={legalInfo?.acnc_registered ?? false}
				/>
				<label class="label-text" for="acnc_registered">Registered with the ACNC</label>
			</div>

			{#if locked('acnc_registered_date')}
				{@render fromRegister(
					'ACNC Registration Date',
					dateOrNull(legalInfo?.acnc_registered_date)
				)}
			{:else}
				<div>
					<label class="label label-text" for="acnc_registered_date">ACNC Registration Date</label>
					<input
						class="input"
						id="acnc_registered_date"
						type="date"
						name="acnc_registered_date"
						value={legalInfo?.acnc_registered_date ?? ''}
					/>
				</div>
			{/if}

			<div class="flex items-center gap-2">
				<input
					class="checkbox"
					id="acnc_status"
					type="checkbox"
					name="acnc_status"
					checked={legalInfo?.acnc_status ?? false}
				/>
				<label class="label-text" for="acnc_status">ACNC registration current</label>
			</div>

			<div>
				<label class="label label-text" for="last_annual_return_date">Last Annual Return</label>
				<input
					class="input"
					id="last_annual_return_date"
					type="date"
					name="last_annual_return_date"
					value={legalInfo?.last_annual_return_date ?? ''}
				/>
			</div>

			{#if locked('dgr_endorsement')}
				{@render fromRegister('DGR endorsed', statusText(legalInfo?.dgr_endorsement, 'Yes', 'No'))}
			{:else}
				<div class="flex items-center gap-2">
					<input
						class="checkbox"
						id="dgr_endorsement"
						type="checkbox"
						name="dgr_endorsement"
						checked={legalInfo?.dgr_endorsement ?? false}
					/>
					<label class="label-text" for="dgr_endorsement">DGR endorsed</label>
				</div>
			{/if}

			<div>
				<label class="label label-text" for="tax_concession_endorsement"
					>Tax Concession Endorsement</label
				>
				<input
					class="input"
					id="tax_concession_endorsement"
					type="date"
					name="tax_concession_endorsement"
					value={legalInfo?.tax_concession_endorsement ?? ''}
				/>
			</div>

			<div>
				<label class="label label-text" for="gst_concession_endorsement_date"
					>GST Concession Endorsement</label
				>
				<input
					class="input"
					id="gst_concession_endorsement_date"
					type="text"
					name="gst_concession_endorsement_date"
					value={legalInfo?.gst_concession_endorsement_date ?? ''}
				/>
			</div>
		</div>
	</fieldset>

	{#if errors?.abn}<p class="text-error-500 text-sm">{errors.abn[0]}</p>{/if}

	<div class="flex justify-end">
		<button class="btn preset-filled" type="submit">Save Changes</button>
	</div>
</form>
