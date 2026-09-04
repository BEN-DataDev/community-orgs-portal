<script lang="ts">
	import { formatDate } from '$lib/utils/formatters';

	interface Props {
		relationships: Array<{
			relationship_id: string;
			partner_org: string | null;
			relationship_type: string | null;
			start_date: string | null;
			end_date: string | null;
		}>;
	}

	let { relationships }: Props = $props();
</script>

<div class="overflow-x-auto">
	<table class="min-w-full divide-y divide-gray-200">
		<thead class="bg-gray-50">
			<tr>
				<th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Partner</th>
				<th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Type</th>
				<th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Duration</th>
			</tr>
		</thead>
		<tbody class="divide-y divide-gray-200 bg-white">
			{#each relationships as relationship (relationship.relationship_id)}
				<tr>
					<td class="px-4 py-2">{relationship.partner_org ?? '—'}</td>
					<td class="px-4 py-2">{relationship.relationship_type ?? '—'}</td>
					<td class="px-4 py-2">
						{relationship.start_date ? formatDate(relationship.start_date) : '—'} –
						{relationship.end_date ? formatDate(relationship.end_date) : 'Present'}
					</td>
				</tr>
			{:else}
				<tr>
					<td class="px-4 py-6 text-center text-gray-500" colspan="3">
						No relationships recorded yet.
					</td>
				</tr>
			{/each}
		</tbody>
	</table>
</div>
