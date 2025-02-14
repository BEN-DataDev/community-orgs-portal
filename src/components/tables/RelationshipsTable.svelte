<script lang="ts">
	import { formatDate } from '$lib/utils/formatters';

	interface Props {
		relationships: Array<{
			relationship_id: number;
			partner_org: string;
			relationship_type: string;
			start_date: string;
			end_date: string | null;
		}>;
	}

	let { relationships }: Props = $props();
</script>

<div class="overflow-x-auto">
	<table class="min-w-full divide-y divide-gray-200">
		<thead class="bg-gray-50">
			<tr>
				<th class="px-4 py-2 text-left text-xs font-medium uppercase text-gray-500"> Partner </th>
				<th class="px-4 py-2 text-left text-xs font-medium uppercase text-gray-500"> Type </th>
				<th class="px-4 py-2 text-left text-xs font-medium uppercase text-gray-500"> Duration </th>
			</tr>
		</thead>
		<tbody class="divide-y divide-gray-200 bg-white">
			{#each relationships as relationship}
				<tr>
					<td class="px-4 py-2">
						<a
							href="/relationships/{relationship.relationship_id}"
							class="text-indigo-600 hover:text-indigo-900"
						>
							{relationship.partner_org}
						</a>
					</td>
					<td class="px-4 py-2">
						{relationship.relationship_type}
					</td>
					<td class="px-4 py-2">
						{formatDate(relationship.start_date)} -
						{relationship.end_date ? formatDate(relationship.end_date) : 'Present'}
					</td>
				</tr>
			{/each}
		</tbody>
	</table>
</div>
