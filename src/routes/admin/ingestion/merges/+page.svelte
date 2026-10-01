<script lang="ts">
	import { enhance } from '$app/forms';
	import { resolve } from '$app/paths';
	import QueueNavigation from '$components/ingestion/QueueNavigation.svelte';
	import type { PageProps } from './$types';
	let { data, form }: PageProps = $props();

	const methodLabel = {
		unique_normalised_name: 'Same name after normalisation',
		trigram_name_similarity: 'Similar name'
	} as const;

	function href(offset: number) {
		const params = new URLSearchParams({ status: data.filter.status, offset: String(offset) });
		if (data.filter.method) params.set('method', data.filter.method);
		return `${resolve('/admin/ingestion/merges')}?${params}`;
	}
	const score = (value: number) => value.toFixed(2);
</script>

<svelte:head><title>Seed merge review</title></svelte:head>
<div class="space-y-6">
	<header class="space-y-2">
		<a class="anchor" href={resolve('/admin/ingestion')}>All ingestion queues</a>
		<h1 class="text-2xl font-bold">Seed merge review</h1>
		<p>
			The seed correction merged NSW incorporated associations into ABN entities by name alone.
			Confirm each merge, or split it if they are different organisations.
		</p>
		<p class="text-sm">
			Responsible role: <strong>Data Steward</strong>. Your decision takes effect immediately; no
			second approval is needed.
		</p>
	</header>
	<QueueNavigation current="merges" />

	<dl class="grid grid-cols-3 gap-3 sm:max-w-md">
		<div class="card preset-tonal p-3">
			<dt class="text-sm">To review</dt>
			<dd class="text-xl font-bold">{data.counts.pending}</dd>
		</div>
		<div class="card preset-tonal p-3">
			<dt class="text-sm">Confirmed</dt>
			<dd class="text-xl font-bold">{data.counts.confirmed}</dd>
		</div>
		<div class="card preset-tonal p-3">
			<dt class="text-sm">Split</dt>
			<dd class="text-xl font-bold">{data.counts.split}</dd>
		</div>
	</dl>

	<form method="GET" class="flex flex-wrap items-end gap-3">
		<label class="label"
			>Status<select class="select" name="status" value={data.filter.status}
				><option value="pending">To review</option><option value="confirmed">Confirmed</option
				><option value="split">Split</option><option value="all">All</option></select
			></label
		>
		<label class="label"
			>Match<select class="select" name="method" value={data.filter.method ?? ''}
				><option value="">Any match</option><option value="trigram_name_similarity"
					>{methodLabel.trigram_name_similarity}</option
				><option value="unique_normalised_name">{methodLabel.unique_normalised_name}</option
				></select
			></label
		>
		<button class="btn preset-filled-primary-500">Show</button>
	</form>

	<!-- A decided merge leaves the "To review" list, so report it here instead. -->
	{#if form?.message && !data.items.some((i) => i.source_organisation_id === form.source)}<p
			role="status"
			class="card preset-tonal p-4"
		>
			{form.message}
		</p>{/if}

	<p>{data.total} {data.total === 1 ? 'merge' : 'merges'} match this filter.</p>
	<ul class="space-y-4">
		{#each data.items as item (item.source_organisation_id)}
			<li class="card border-surface-200-800 space-y-4 border p-4">
				<div class="grid gap-4 md:grid-cols-2">
					<section class="min-w-0 space-y-1">
						<h2 class="text-sm font-semibold uppercase">NSW association (merged away)</h2>
						<p class="text-lg font-bold break-words">{item.source_name}</p>
						<p class="text-sm">
							Incorporation number {item.incorporation_number ?? '—'}{#if item.registration_date}
								· registered {item.registration_date}{/if}
						</p>
						{#if item.source_entity_type}<p class="text-sm">{item.source_entity_type}</p>{/if}
						{#if item.source_website}<p class="text-sm break-all">{item.source_website}</p>{/if}
					</section>
					<section class="min-w-0 space-y-1">
						<h2 class="text-sm font-semibold uppercase">Merged into ABN entity</h2>
						<p class="text-lg font-bold break-words">
							<a
								class="anchor"
								href={resolve('/organisations/[id]', { id: item.target_organisation_id })}
								>{item.target_name ?? 'Organisation missing'}</a
							>
						</p>
						<p class="text-sm">ABN {item.target_abn ?? '—'}</p>
						{#if item.target_entity_type}<p class="text-sm">{item.target_entity_type}</p>{/if}
					</section>
				</div>
				<p class="text-sm">
					{methodLabel[item.match_method]}{#if item.match_method === 'trigram_name_similarity'}
						· similarity {score(item.similarity_score)}{#if item.second_similarity_score !== null}
							(next best {score(item.second_similarity_score)}){/if}{/if}
				</p>

				{#if form?.message && form.source === item.source_organisation_id}<p
						role="status"
						class="card preset-tonal p-3"
					>
						{form.message}
					</p>{/if}

				{#if item.decision}
					<p class="text-sm">
						<strong>{item.decision === 'split' ? 'Split' : 'Confirmed'}</strong>
						{#if item.reviewed_at}on {new Date(
								item.reviewed_at
							).toLocaleDateString()}{/if}{#if item.note}
							· {item.note}{/if}
					</p>
				{:else}
					<form method="POST" use:enhance class="space-y-3">
						<input type="hidden" name="source" value={item.source_organisation_id} />
						<label class="label"
							>Note (required to split)<textarea
								class="textarea"
								name="note"
								maxlength="2000"
								rows="2"
							></textarea></label
						>
						<div class="flex flex-wrap gap-3">
							<button class="btn preset-filled-success-500" name="decision" value="confirmed"
								>Confirm: same organisation</button
							>
							<button class="btn preset-filled-warning-500" name="decision" value="split"
								>Split: different organisations</button
							>
						</div>
					</form>
				{/if}
			</li>
		{:else}
			<li>No merges match this filter.</li>
		{/each}
	</ul>

	<nav class="flex gap-4" aria-label="Merge pages">
		{#if data.filter.offset > 0}<a
				class="anchor"
				href={href(Math.max(0, data.filter.offset - data.pageSize))}>Previous</a
			>{/if}
		{#if data.filter.offset + data.pageSize < data.total}<a
				class="anchor"
				href={href(data.filter.offset + data.pageSize)}>Next</a
			>{/if}
	</nav>
</div>
