<script lang="ts">
	import { resolve } from '$app/paths';
	import QueueNavigation from '$components/ingestion/QueueNavigation.svelte';
	import type { PageProps } from './$types';

	let { data, form }: PageProps = $props();
	const pageSize = 50;
	function href(options: {
		release?: string;
		version?: string;
		decision?: string;
		offset?: number;
	}) {
		const params = new URLSearchParams();
		const release = options.release ?? data.queue.release_id;
		if (release) params.set('release', release);
		if (options.version) params.set('version', options.version);
		const decision = options.decision ?? data.decision;
		if (decision !== 'all') params.set('decision', decision);
		if (options.offset) params.set('offset', String(options.offset));
		return `${resolve('/admin/ingestion/candidates')}?${params}`;
	}
	function display(value: unknown) {
		return typeof value === 'string' ? value : JSON.stringify(value);
	}
</script>

<svelte:head><title>Registry seed triage</title></svelte:head>

<div class="space-y-6">
	<header class="space-y-2">
		<a class="anchor" href={resolve('/admin/ingestion')}>Back to ingestion queues</a>
		<h1 class="text-2xl font-bold">Registry seed triage</h1>
		<p class="text-surface-600-400">
			Decide whether private ABN and state-register candidates belong in the bounded cohort.
			Suggestions are evidence for review and never create an automatic name match.
		</p>
	</header>

	<QueueNavigation current="candidates" />

	{#if form?.message}
		<p class="card preset-tonal p-3" role="status">{form.message}</p>
	{/if}

	<section class="card preset-outlined space-y-4 p-4" aria-labelledby="filters-heading">
		<h2 id="filters-heading" class="font-semibold">Queue filters</h2>
		<form method="GET" class="grid gap-3 md:grid-cols-[2fr_1fr_auto] md:items-end">
			<label>
				<span class="mb-1 block text-sm font-medium">Seed release</span>
				<select class="select" name="release">
					{#each data.queue.releases as release}
						<option value={release.id} selected={release.id === data.queue.release_id}>
							{release.source_id} · {release.release_key} · {release.completion} · {release.candidate_count}
						</option>
					{/each}
				</select>
			</label>
			<label>
				<span class="mb-1 block text-sm font-medium">Decision</span>
				<select class="select" name="decision">
					{#each ['all', 'pending', 'include', 'exclude', 'defer', 'link'] as decision}
						<option value={decision} selected={decision === data.decision}>{decision}</option>
					{/each}
				</select>
			</label>
			<button class="btn preset-filled-primary-500" type="submit">Apply</button>
		</form>
	</section>

	<div class="grid gap-5 xl:grid-cols-[minmax(18rem,0.8fr)_minmax(0,1.7fr)]">
		<section class="card preset-outlined space-y-3 p-4" aria-labelledby="candidate-list">
			<h2 id="candidate-list" class="font-semibold">Candidates ({data.queue.total})</h2>
			<ul class="space-y-2">
				{#each data.queue.records as candidate}
					<li>
						<a
							class={`rounded-base border-surface-200-800 block border p-3 ${candidate.version_id === data.queue.detail?.version_id ? 'preset-tonal-primary' : 'hover:preset-tonal'}`}
							href={href({ version: candidate.version_id, offset: data.queue.offset })}
						>
							<span class="block font-medium">{candidate.name}</span>
							<span class="text-surface-600-400 block text-sm">{candidate.native_id}</span>
							<span class="text-sm"
								>{candidate.decision}{candidate.promoted ? ' · promoted' : ''}</span
							>
						</a>
					</li>
				{:else}
					<li class="text-surface-600-400">No candidates match this filter.</li>
				{/each}
			</ul>
			<nav aria-label="Candidate pages" class="flex justify-between">
				{#if data.queue.offset > 0}
					<a class="anchor" href={href({ offset: Math.max(0, data.queue.offset - pageSize) })}
						>Previous</a
					>
				{:else}<span></span>{/if}
				{#if data.queue.offset + data.queue.records.length < data.queue.total}
					<a class="anchor" href={href({ offset: data.queue.offset + pageSize })}>Next</a>
				{/if}
			</nav>
		</section>

		<section class="card preset-outlined space-y-5 p-5" aria-labelledby="candidate-detail">
			{#if data.queue.detail}
				{@const detail = data.queue.detail}
				<header>
					<p class="text-surface-600-400 text-sm">{detail.source_id}/{detail.resource_id}</p>
					<h2 id="candidate-detail" class="text-xl font-semibold">{detail.native_id}</h2>
					<p class="text-sm">{detail.selection_reasons.join(' · ')}</p>
				</header>

				<div>
					<h3 class="font-semibold">Mapped assertions</h3>
					<dl class="mt-2 grid gap-2 sm:grid-cols-2">
						{#each detail.payload.assertions as assertion}
							<div class="bg-surface-100-900 rounded-base p-3">
								<dt class="text-sm font-medium">{assertion.field}</dt>
								<dd class="text-sm break-words">{display(assertion.value)}</dd>
							</div>
						{/each}
					</dl>
				</div>

				<div class="space-y-2">
					<h3 class="font-semibold">Cross-source suggestions</h3>
					{#each detail.suggestions as suggestion}
						<div class="preset-tonal rounded-base p-3 text-sm">
							<p class="font-medium">{suggestion.name}</p>
							<p>{suggestion.source_id} · {suggestion.native_id} · candidate {suggestion.id}</p>
							<p>{suggestion.reason}</p>
						</div>
					{:else}
						<p class="text-surface-600-400 text-sm">No exact-identifier or same-name suggestion.</p>
					{/each}
				</div>

				<form method="POST" action="?/triage" class="space-y-4">
					<input type="hidden" name="release" value={detail.release_id} />
					<input type="hidden" name="version" value={detail.version_id} />
					<input type="hidden" name="revision" value={detail.triage?.revision ?? 0} />
					<div class="grid gap-3 sm:grid-cols-2">
						<label>
							<span class="mb-1 block text-sm font-medium">Decision</span>
							<select class="select" name="decision" required>
								{#each ['include', 'exclude', 'defer', 'link'] as decision}
									<option value={decision} selected={decision === detail.triage?.decision}
										>{decision}</option
									>
								{/each}
							</select>
						</label>
						<label>
							<span class="mb-1 block text-sm font-medium">Link target type</span>
							<select class="select" name="targetKind">
								<option
									value=""
									selected={!detail.triage?.target_candidate_id && !detail.triage?.target_record_id}
									>No target</option
								>
								<option value="candidate" selected={Boolean(detail.triage?.target_candidate_id)}
									>Registry candidate</option
								>
								<option value="record" selected={Boolean(detail.triage?.target_record_id)}
									>Promoted source record</option
								>
							</select>
						</label>
					</div>
					<label>
						<span class="mb-1 block text-sm font-medium">Link target ID</span>
						<input
							class="input"
							name="targetId"
							inputmode="numeric"
							pattern="[1-9][0-9]*"
							list="candidate-suggestions"
							value={detail.triage?.target_candidate_id ?? detail.triage?.target_record_id ?? ''}
						/>
						<datalist id="candidate-suggestions">
							{#each detail.suggestions as suggestion}<option value={suggestion.id}
									>{suggestion.name}</option
								>{/each}
						</datalist>
					</label>
					<label>
						<span class="mb-1 block text-sm font-medium">Evidence note</span>
						<textarea class="textarea" name="note" rows="3" maxlength="2000" required
							>{detail.triage?.note ?? ''}</textarea
						>
					</label>
					<button class="btn preset-filled-primary-500" type="submit">Save triage decision</button>
				</form>

				{#if detail.triage?.decision === 'include' || detail.triage?.decision === 'link'}
					<form
						method="POST"
						action="?/promote"
						class="preset-tonal-warning rounded-base space-y-3 p-4"
					>
						<input type="hidden" name="release" value={detail.release_id} />
						<input type="hidden" name="version" value={detail.version_id} />
						<h3 class="font-semibold">Promote to private ingestion</h3>
						<p class="text-sm">This does not create or publish an organisation.</p>
						<label>
							<span class="mb-1 block text-sm font-medium">Promotion reason</span>
							<textarea class="textarea" name="reason" rows="2" maxlength="2000" required
							></textarea>
						</label>
						<button class="btn preset-filled-warning-500" type="submit" disabled={detail.promoted}>
							{detail.promoted ? 'Already promoted' : 'Promote candidate'}
						</button>
					</form>
				{/if}
			{:else}
				<h2 id="candidate-detail" class="font-semibold">No candidate selected</h2>
				<p class="text-surface-600-400">Choose a release with candidates to begin triage.</p>
			{/if}
		</section>
	</div>
</div>
