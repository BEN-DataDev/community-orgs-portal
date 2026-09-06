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

<!--
	This renders inside a narrow sidebar card on the organisation overview, so
	it is cramped on desktop as well as on phones. A container query keyed to
	its own width is therefore the right trigger, not a viewport breakpoint —
	it stacks whenever the space is tight, wherever that happens.
-->
<div class="@container">
	<div class="space-y-2 @md:hidden">
		{#each relationships as relationship (relationship.relationship_id)}
			<div class="card preset-outlined-surface-200-800 p-3">
				<div class="font-medium">{relationship.partner_org ?? '—'}</div>
				<dl class="mt-1 grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 text-sm">
					<dt class="text-surface-600-400">Type</dt>
					<dd>{relationship.relationship_type ?? '—'}</dd>
					<dt class="text-surface-600-400">Duration</dt>
					<dd>
						{relationship.start_date ? formatDate(relationship.start_date) : '—'} –
						{relationship.end_date ? formatDate(relationship.end_date) : 'Present'}
					</dd>
				</dl>
			</div>
		{:else}
			<p class="card preset-outlined-surface-200-800 text-surface-600-400 p-4 text-center text-sm">
				No relationships recorded yet.
			</p>
		{/each}
	</div>

	<div class="table-wrap hidden @md:block">
		<table class="table">
			<thead>
				<tr>
					<th>Partner</th>
					<th>Type</th>
					<th>Duration</th>
				</tr>
			</thead>
			<tbody>
				{#each relationships as relationship (relationship.relationship_id)}
					<tr>
						<td>{relationship.partner_org ?? '—'}</td>
						<td>{relationship.relationship_type ?? '—'}</td>
						<td class="whitespace-nowrap">
							{relationship.start_date ? formatDate(relationship.start_date) : '—'} –
							{relationship.end_date ? formatDate(relationship.end_date) : 'Present'}
						</td>
					</tr>
				{:else}
					<tr>
						<td class="text-surface-600-400 text-center" colspan="3">
							No relationships recorded yet.
						</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</div>
</div>
