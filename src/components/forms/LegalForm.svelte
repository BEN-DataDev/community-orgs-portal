<script lang="ts">
	import { enhance } from '$app/forms';

	interface Props {
		legalInfo: any;
		onSave?: () => void;
	}

	let { legalInfo, onSave }: Props = $props();

	let documents = $state(legalInfo.documents || []);

	function addDocument() {
		documents = [...documents, { name: '', url: '' }];
	}

	function removeDocument(index: number) {
		documents = documents.filter((_: any, i: number) => i !== index);
	}
</script>

<form
	method="POST"
	action="?/updateLegal"
	use:enhance={() => {
		return ({ result }: { result: { type: string } }) => {
			if (result.type === 'success') {
				onSave?.();
			}
		};
	}}
	class="space-y-6"
>
	<input type="hidden" name="orgId" value={legalInfo.org_id} />
	<input type="hidden" name="documents" value={JSON.stringify(documents)} />

	<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
		<div>
			<label for="entity_type">Entity Type</label>
			<select id="entity_type" name="entity_type" value={legalInfo.entity_type} required>
				<option value="Company">Company</option>
				<option value="Trust">Trust</option>
				<option value="Association">Association</option>
				<option value="Partnership">Partnership</option>
			</select>
		</div>

		<div>
			<label for="abn">ABN</label>
			<input id="abn" type="text" name="abn" value={legalInfo.abn} required />
		</div>

		<div>
			<label for="acn">ACN</label>
			<input id="acn" type="text" name="acn" value={legalInfo.acn} />
		</div>

		<div>
			<label for="registration_date">Registration Date</label>
			<input
				id="registration_date"
				type="date"
				name="registration_date"
				value={legalInfo.registration_date}
				required
			/>
		</div>

		<div>
			<label for="tax_status">Tax Status</label>
			<select id="tax_status" name="tax_status" value={legalInfo.tax_status} required>
				<option value="For-Profit">For-Profit</option>
				<option value="Non-Profit">Non-Profit</option>
				<option value="Charity">Charity</option>
			</select>
		</div>

		<div>
			<label for="charity_status">Charity Status</label>
			<select id="charity_status" name="charity_status" value={legalInfo.charity_status}>
				<option value="Registered">Registered</option>
				<option value="Not Registered">Not Registered</option>
			</select>
		</div>
	</div>

	<div>
		<h3 class="mb-2 font-medium">Legal Documents</h3>
		{#each documents as doc, index}
			<div class="mb-2 flex gap-4">
				<input
					type="text"
					bind:value={doc.name}
					placeholder="Document name"
					aria-label="Document name"
				/>
				<input
					type="url"
					bind:value={doc.url}
					placeholder="Document URL"
					aria-label="Document URL"
				/>
				<button
					type="button"
					class="variant-filled-warning btn"
					onclick={() => removeDocument(index)}
				>
					Remove
				</button>
			</div>
		{/each}
		<button type="button" class="variant-filled btn" onclick={addDocument}>Add Document</button>
	</div>

	<div class="flex justify-end">
		<button type="submit">Save Changes</button>
	</div>
</form>
