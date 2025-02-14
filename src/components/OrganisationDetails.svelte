<script lang="ts">
	import { enhance } from '$app/forms';

	interface Props {
		organisation: {
			org_id: number;
			legal_name: string;
			trading_name: string | null;
			date_established: string;
			legal_details: any;
			contact_info: any;
			operational_details: any;
			financial_info: any;
		};
		onSave?: () => void;
		isEditing?: boolean;
	}

	let { organisation, onSave, isEditing = false }: Props = $props();

	let formData = $state({ ...organisation });
</script>

<div class="space-y-6">
	{#if isEditing}
		<form method="POST" action="?/updateOrganisation" use:enhance class="space-y-6">
			<input type="hidden" name="orgId" value={organisation.org_id} />

			<card title="Basic Information">
				<div class="space-y-4">
					<div>
						<label for="legal_name">Legal Name</label>
						<input
							type="text"
							id="legal_name"
							name="legal_name"
							bind:value={formData.legal_name}
							class="input"
						/>
					</div>
					<div>
						<label for="trading_name">Trading Name</label>
						<input
							type="text"
							id="trading_name"
							name="trading_name"
							bind:value={formData.trading_name}
							class="input"
						/>
					</div>
				</div>
			</card>

			<!-- Additional form sections for other details -->

			<div class="flex justify-end">
				<button type="submit" class="variant-filled btn">Save Changes</button>
			</div>
		</form>
	{:else}
		<card title="Basic Information">
			<div class="space-y-2">
				<div>
					<span class="font-medium">Legal Name:</span>
					{organisation.legal_name}
				</div>
				{#if organisation.trading_name}
					<div>
						<span class="font-medium">Trading Name:</span>
						{organisation.trading_name}
					</div>
				{/if}
				<div>
					<span class="font-medium">Established:</span>
					{new Date(organisation.date_established).toLocaleDateString()}
				</div>
			</div>
		</card>

		<!-- Additional display cards for other details -->
	{/if}
</div>
