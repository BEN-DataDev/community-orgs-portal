<script lang="ts">
	import { resolve } from '$app/paths';
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

<!--
	Below `md` each row becomes a card. The previous markup was
	`overflow-x-auto` + `min-w-full`, which compresses four columns of
	two-line cells to unreadable widths instead of ever engaging the scroll.
-->
<div class="space-y-3 md:hidden">
	{#each organisations as org (org.org_id)}
		{@const legal = org.legal_details?.[0]}
		{@const contact = org.contact_info?.[0]}
		{@const trading = org.aliases?.find((a) => a.alias_type === 'Trading Name')}
		<div class="card preset-outlined-surface-200-800 space-y-3 p-4">
			<div>
				<a class="anchor font-medium" href={resolve('/organisations/[id]', { id: org.org_id })}
					>{org.entity_name}</a
				>
				{#if trading?.alias}
					<div class="text-surface-600-400 text-sm">Trading as: {trading.alias}</div>
				{/if}
			</div>

			<dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
				<dt class="text-surface-600-400">Entity type</dt>
				<dd>{legal?.entity_type ?? '—'}</dd>
				<dt class="text-surface-600-400">ABN</dt>
				<dd>{legal?.abn ?? '—'}</dd>
				<dt class="text-surface-600-400">Email</dt>
				<dd class="break-words">{contact?.email ?? '—'}</dd>
				<dt class="text-surface-600-400">Phone</dt>
				<dd>{phoneOf(contact?.phone)}</dd>
			</dl>
		</div>
	{:else}
		<p class="card preset-outlined-surface-200-800 text-surface-600-400 p-6 text-center">
			No organisations recorded yet.
		</p>
	{/each}
</div>

<div class="table-wrap hidden md:block">
	<table class="table">
		<thead>
			<tr>
				<th>Organisation</th>
				<th>Entity Type</th>
				<th>Contact</th>
				<th>Actions</th>
			</tr>
		</thead>
		<tbody class="[&>tr]:hover:preset-tonal">
			{#each organisations as org (org.org_id)}
				{@const legal = org.legal_details?.[0]}
				{@const contact = org.contact_info?.[0]}
				{@const trading = org.aliases?.find((a) => a.alias_type === 'Trading Name')}
				<tr>
					<td>
						<div class="font-medium">{org.entity_name}</div>
						{#if trading?.alias}
							<div class="text-surface-600-400 text-sm">Trading as: {trading.alias}</div>
						{/if}
					</td>
					<td>
						<div>{legal?.entity_type ?? '—'}</div>
						<div class="text-surface-600-400 text-sm">ABN: {legal?.abn ?? '—'}</div>
					</td>
					<td>
						<div class="break-words">{contact?.email ?? '—'}</div>
						<div class="text-surface-600-400 text-sm">{phoneOf(contact?.phone)}</div>
					</td>
					<td>
						<a class="anchor" href={resolve('/organisations/[id]', { id: org.org_id })}
							>View Details</a
						>
					</td>
				</tr>
			{:else}
				<tr>
					<td class="text-surface-600-400 text-center" colspan="4">
						No organisations recorded yet.
					</td>
				</tr>
			{/each}
		</tbody>
	</table>
</div>
