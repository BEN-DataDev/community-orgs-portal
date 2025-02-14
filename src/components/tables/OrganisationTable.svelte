<script lang="ts">
	interface Props {
		organisations: Array<{
			org_id: number;
			legal_name: string;
			trading_name: string | null;
			date_established: string;
			legal_details: {
				entity_type: string;
				abn: string;
			};
			contact_info: {
				phone: string;
				email: string;
			};
		}>;
	}

	let { organisations }: Props = $props();
</script>

<div class="overflow-x-auto">
	<table class="min-w-full divide-y divide-gray-200">
		<thead class="bg-gray-50">
			<tr>
				<th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">
					Organisation
				</th>
				<th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">
					Entity Type
				</th>
				<th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">
					Contact
				</th>
				<th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">
					Actions
				</th>
			</tr>
		</thead>
		<tbody class="divide-y divide-gray-200 bg-white">
			{#each organisations as org}
				<tr>
					<td class="px-6 py-4">
						<div>
							<div class="font-medium">{org.legal_name}</div>
							{#if org.trading_name}
								<div class="text-sm text-gray-500">{org.trading_name}</div>
							{/if}
						</div>
					</td>
					<td class="px-6 py-4">
						<div>
							<div>{org.legal_details.entity_type}</div>
							<div class="text-sm text-gray-500">ABN: {org.legal_details.abn}</div>
						</div>
					</td>
					<td class="px-6 py-4">
						<div>
							<div>{org.contact_info.email}</div>
							<div class="text-sm text-gray-500">{org.contact_info.phone}</div>
						</div>
					</td>
					<td class="px-6 py-4">
						<a href="/organisations/{org.org_id}" class="text-indigo-600 hover:text-indigo-900">
							View Details
						</a>
					</td>
				</tr>
			{/each}
		</tbody>
	</table>
</div>
