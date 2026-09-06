<script lang="ts">
	import LegalForm from '$components/forms/LegalForm.svelte';
	import { EDITOR_LEVEL } from '$lib/role-levels';
	import { formatDate } from '$lib/utils/formatters';

	let { data, form } = $props();
	let { legalInfo, documents, organisation, roleLevel } = $derived(data);
	let canEdit = $derived(roleLevel >= EDITOR_LEVEL);
	let isEditing = $state(false);

	const yesNo = (value: boolean | null) => (value === null ? '—' : value ? 'Yes' : 'No');
	const orDash = (value: string | null) => (value ? formatDate(value) : '—');
</script>

<div>
	<div class="mb-6 flex items-center justify-between">
		<div>
			<h1 class="text-2xl font-bold">Legal Information</h1>
			<p class="text-gray-600">{organisation.entity_name}</p>
		</div>
		{#if canEdit}
			<button class="btn preset-filled" onclick={() => (isEditing = !isEditing)}>
				{isEditing ? 'Cancel' : 'Edit Legal Info'}
			</button>
		{/if}
	</div>

	{#if form?.message}
		<p class="mb-4 text-red-600">{form.message}</p>
	{/if}

	{#if isEditing && canEdit}
		<LegalForm {legalInfo} errors={form?.errors} onSave={() => (isEditing = false)} />
	{:else}
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
			<div class="space-y-2 rounded-lg border p-4">
				<h2 class="font-medium">Entity Details</h2>
				<p><strong>Entity Type:</strong> {legalInfo?.entity_type ?? '—'}</p>
				<p><strong>Charity Type:</strong> {legalInfo?.charity_type ?? '—'}</p>
				<p>
					<strong>ABN:</strong>
					{legalInfo?.abn ?? '—'} ({yesNo(legalInfo?.abn_status ?? null)})
				</p>
				<p><strong>ABN Activated:</strong> {orDash(legalInfo?.abn_activated ?? null)}</p>
				<p><strong>ACN:</strong> {legalInfo?.acn ?? '—'}</p>
			</div>

			<div class="space-y-2 rounded-lg border p-4">
				<h2 class="font-medium">Incorporation</h2>
				<p><strong>Number:</strong> {legalInfo?.incorporation_number ?? '—'}</p>
				<p><strong>Incorporated:</strong> {yesNo(legalInfo?.incorporation_status ?? null)}</p>
				<p>
					<strong>Registered:</strong>
					{orDash(legalInfo?.incorporation_registration_date ?? null)}
				</p>
			</div>

			<div class="space-y-2 rounded-lg border p-4">
				<h2 class="font-medium">ACNC &amp; Concessions</h2>
				<p><strong>ACNC Registered:</strong> {yesNo(legalInfo?.acnc_registered ?? null)}</p>
				<p><strong>ACNC Date:</strong> {orDash(legalInfo?.acnc_registered_date ?? null)}</p>
				<p><strong>Registration Current:</strong> {yesNo(legalInfo?.acnc_status ?? null)}</p>
				<p>
					<strong>Last Annual Return:</strong>
					{orDash(legalInfo?.last_annual_return_date ?? null)}
				</p>
				<p><strong>DGR Endorsed:</strong> {yesNo(legalInfo?.dgr_endorsement ?? null)}</p>
				<p>
					<strong>Tax Concession:</strong>
					{orDash(legalInfo?.tax_concession_endorsement ?? null)}
				</p>
				<p>
					<strong>GST Concession:</strong>
					{legalInfo?.gst_concession_endorsement_date ?? '—'}
				</p>
			</div>

			<div class="space-y-3 rounded-lg border p-4">
				<h2 class="font-medium">Documents</h2>
				{#each documents as document (document.document_id)}
					<div class="flex items-center justify-between gap-3 border-b pb-2 last:border-0">
						<a
							href={document.url}
							rel="noopener noreferrer"
							target="_blank"
							class="text-indigo-600 hover:text-indigo-900"
						>
							{document.name}
						</a>
						{#if canEdit}
							<form method="POST" action="?/deleteDocument">
								<input type="hidden" name="document_id" value={document.document_id} />
								<button type="submit" class="text-sm text-red-600 hover:underline">Remove</button>
							</form>
						{/if}
					</div>
				{:else}
					<p class="text-gray-600">No documents recorded.</p>
				{/each}

				{#if canEdit}
					<form method="POST" action="?/addDocument" class="space-y-2 border-t pt-3">
						<div>
							<label for="document_name">Document name</label>
							<input id="document_name" name="name" type="text" required />
						</div>
						<div>
							<label for="document_url">Document URL</label>
							<input id="document_url" name="url" type="url" required />
							{#if form?.errors?.url}
								<p class="text-sm text-red-600">{form.errors.url[0]}</p>
							{/if}
						</div>
						<button type="submit" class="btn preset-filled">Add Document</button>
					</form>
				{/if}
			</div>
		</div>
	{/if}
</div>
