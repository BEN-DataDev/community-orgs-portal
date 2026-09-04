<script lang="ts">
	/**
	 * `legal_details`, `contact_info` and `aliases` are child tables joined on
	 * `org_id`, so PostgREST returns an array for each embed — not an object.
	 */
	interface Props {
		organisations: Array<{
			org_id: string;
			entity_name: string;
			slug: string;
			description: string | null;
			date_established: string | null;
			is_public: boolean;
			legal_details: Array<{ entity_type: string | null; abn: string | null }> | null;
			contact_info: Array<{ phone: unknown; email: string | null }> | null;
			aliases: Array<{ alias: string | null; alias_type: string | null }> | null;
		}>;
	}

	let { organisations }: Props = $props();

	/** `contact_info.phone` is jsonb, stored as `{ primary: "..." }`. */
	function phoneOf(phone: unknown): string {
		if (phone && typeof phone === 'object' && 'primary' in phone) {
			const primary = (phone as { primary?: unknown }).primary;
			if (typeof primary === 'string') return primary;
		}
		return '—';
	}
</script>

<div class="overflow-x-auto">
	<table class="min-w-full divide-y divide-gray-200">
		<thead class="bg-gray-50">
			<tr>
				<th class="px-6 py-3 text-left text-xs font-medium tracking-wider text-gray-500 uppercase">
					Organisation
				</th>
				<th class="px-6 py-3 text-left text-xs font-medium tracking-wider text-gray-500 uppercase">
					Entity Type
				</th>
				<th class="px-6 py-3 text-left text-xs font-medium tracking-wider text-gray-500 uppercase">
					Contact
				</th>
				<th class="px-6 py-3 text-left text-xs font-medium tracking-wider text-gray-500 uppercase">
					Actions
				</th>
			</tr>
		</thead>
		<tbody class="divide-y divide-gray-200 bg-white">
			{#each organisations as org (org.org_id)}
				{@const legal = org.legal_details?.[0]}
				{@const contact = org.contact_info?.[0]}
				{@const trading = org.aliases?.find((a) => a.alias_type === 'Trading Name')}
				<tr>
					<td class="px-6 py-4">
						<div>
							<div class="font-medium">{org.entity_name}</div>
							{#if trading?.alias}
								<div class="text-sm text-gray-500">Trading as: {trading.alias}</div>
							{/if}
						</div>
					</td>
					<td class="px-6 py-4">
						<div>
							<div>{legal?.entity_type ?? '—'}</div>
							<div class="text-sm text-gray-500">ABN: {legal?.abn ?? '—'}</div>
						</div>
					</td>
					<td class="px-6 py-4">
						<div>
							<div>{contact?.email ?? '—'}</div>
							<div class="text-sm text-gray-500">{phoneOf(contact?.phone)}</div>
						</div>
					</td>
					<td class="px-6 py-4">
						<a href="/organisations/{org.org_id}" class="text-indigo-600 hover:text-indigo-900">
							View Details
						</a>
					</td>
				</tr>
			{:else}
				<tr>
					<td class="px-6 py-8 text-center text-gray-500" colspan="4">
						No organisations recorded yet.
					</td>
				</tr>
			{/each}
		</tbody>
	</table>
</div>
