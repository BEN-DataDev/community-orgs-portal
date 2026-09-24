<script lang="ts">
	import { enhance } from '$app/forms';
	import { resolve } from '$app/paths';
	import QueueNavigation from '$components/ingestion/QueueNavigation.svelte';
	import type { PageProps } from './$types';
	let { data, form }: PageProps = $props();
	const queue = $derived(data.queue);
	function href(run: string, version?: string, offset = data.offset) {
		const params = new URLSearchParams({ run, offset: String(offset) });
		if (version) params.set('version', version);
		if (data.search) params.set('search', data.search);
		if (data.campaign) params.set('campaign', data.campaign);
		return `${resolve('/admin/ingestion/identity')}?${params}`;
	}
	function changesHref(target = '') {
		const params = new URLSearchParams({ run: queue.run!, version: queue.detail!.id });
		params.set('target', target);
		if (data.campaign) params.set('campaign', data.campaign);
		return `${resolve('/admin/ingestion/changes')}?${params}`;
	}
</script>

<svelte:head><title>Identity and eligibility queue</title></svelte:head>
<div class="space-y-6">
	<header class="space-y-2">
		<a class="anchor" href={resolve('/admin/ingestion')}>All ingestion queues</a>
		<h1 class="text-2xl font-bold">Identity and eligibility queue</h1>
		<p>Primary decision: link, create, defer or reject each staged record.</p>
		<p class="text-sm">
			Next responsible role: <strong>Data Steward</strong>. Saving does not publish data.
		</p>
	</header>
	<QueueNavigation
		current="identity"
		campaign={data.campaign}
		run={queue.run ?? ''}
		version={queue.detail?.id ?? ''}
	/>
	{#if form?.message}<p role="status" class="card preset-tonal p-4">{form.message}</p>{/if}
	<form method="GET" class="flex flex-wrap items-end gap-3">
		{#if data.campaign}<input type="hidden" name="campaign" value={data.campaign} />{/if}
		<label class="label flex-1"
			>Import run<select class="select" name="run" value={queue.run ?? ''} required>
				{#each queue.runs as run}<option value={run.id}
						>Run {run.id} · {run.run_key} · {run.completion}</option
					>{/each}
			</select></label
		><button class="btn preset-filled-primary-500" disabled={!queue.runs.length}>Open run</button>
	</form>
	{#if !queue.runs.length}<p>No staged runs are available.</p>{:else}
		<p>{queue.total} staged records.</p>
		<div class="grid gap-6 xl:grid-cols-[minmax(16rem,1fr)_2fr]">
			<section aria-label="Identity queue" class="space-y-3">
				<ul class="space-y-2">
					{#each queue.records as record}<li>
							<a
								class="card border-surface-200-800 hover:preset-tonal block border p-3"
								href={href(queue.run!, record.id)}
								aria-current={queue.detail?.id === record.id ? 'page' : undefined}
								><strong>{record.name}</strong><span class="block text-sm"
									>Source ID {record.native_id} · {record.decision}</span
								></a
							>
						</li>{/each}
				</ul>
				<nav aria-label="Record pages" class="flex gap-4">
					{#if data.offset > 0}<a
							class="anchor"
							href={href(queue.run!, undefined, Math.max(0, data.offset - 50))}>Previous</a
						>{/if}{#if data.offset + 50 < queue.total}<a
							class="anchor"
							href={href(queue.run!, undefined, data.offset + 50)}>Next</a
						>{/if}
				</nav>
			</section>
			<section aria-label="Identity decision" class="min-w-0 space-y-4">
				{#if queue.detail}
					<h2 class="text-xl font-bold">Source record {queue.detail.native_id}</h2>
					{#if queue.detail.identity_match}<div class="card preset-tonal p-4">
							<strong>Automated assessment: {queue.detail.identity_match.status}</strong>
							<p>{queue.detail.identity_match.reason}</p>
						</div>{/if}
					<details class="card preset-tonal p-4">
						<summary class="cursor-pointer font-semibold">Source evidence</summary>
						<dl class="mt-3 grid gap-2">
							{#each queue.detail.payload.assertions as assertion}<div>
									<dt class="font-medium">{assertion.field}</dt>
									<dd class="break-all">
										{typeof assertion.value === 'string'
											? assertion.value
											: JSON.stringify(assertion.value)}
									</dd>
								</div>{/each}
						</dl>
					</details>
					<form method="GET" class="flex flex-wrap items-end gap-3">
						<input type="hidden" name="run" value={queue.run!} /><input
							type="hidden"
							name="version"
							value={queue.detail.id}
						/>{#if data.campaign}<input
								type="hidden"
								name="campaign"
								value={data.campaign}
							/>{/if}<label class="label flex-1"
							>Find an organisation by name<input
								class="input"
								name="search"
								value={data.search}
								minlength="2"
								maxlength="100"
							/></label
						><button class="btn preset-tonal">Search</button>
					</form>
					<div class="space-y-3">
						<h3 class="font-semibold">Possible matches</h3>
						{#each queue.candidates as candidate}<article
								class="card border-surface-200-800 border p-4"
							>
								<h4 class="font-semibold">{candidate.entity_name}</h4>
								<p>{candidate.reason}</p>
								<p class="text-sm">
									ABN: {candidate.abn ?? 'None'} · {candidate.physical_address ??
										candidate.postal_address ??
										'No address'}
								</p>
								<a class="anchor" href={changesHref(candidate.org_id)}
									>Compare fields in field-change queue</a
								>
							</article>{:else}<p>
								No candidates found. Search before proposing a new organisation.
							</p>{/each}
					</div>
					<form method="POST" use:enhance class="card preset-tonal space-y-4 p-4">
						<input type="hidden" name="run" value={queue.run!} /><input
							type="hidden"
							name="version"
							value={queue.detail.id}
						/><input
							type="hidden"
							name="revision"
							value={queue.detail.review?.revision ?? 0}
						/><label class="label"
							>Decision<select
								class="select"
								name="decision"
								required
								value={queue.detail.review?.decision ?? ''}
								><option value="" disabled>Select a decision</option><option value="link"
									>Link existing organisation</option
								><option value="create">Create new organisation</option><option value="defer"
									>Defer for investigation</option
								><option value="reject">Reject this version</option></select
							></label
						><label class="label"
							>Organisation (link only)<select
								class="select"
								name="organisation"
								value={queue.detail.review?.organisation_id ??
									queue.detail.identity_match?.organisation_id ??
									''}
								><option value="">No organisation selected</option
								>{#if queue.detail.review?.organisation_id && !queue.candidates.some((item) => item.org_id === queue.detail!.review?.organisation_id)}<option
										value={queue.detail.review.organisation_id}
										>Previously selected: {queue.detail.review.organisation_id}</option
									>{/if}{#each queue.candidates as candidate}<option value={candidate.org_id}
										>{candidate.entity_name} · {candidate.abn ?? candidate.org_id}</option
									>{/each}</select
							></label
						><label class="label"
							>Reason and eligibility checks<textarea
								class="textarea"
								name="note"
								rows="4"
								required
								maxlength="2000"
								value={queue.detail.review?.note ?? ''}
							></textarea></label
						><button class="btn preset-filled-primary-500">Save identity decision</button>
					</form>
					{#if queue.detail.review && ['link', 'create'].includes(queue.detail.review.decision)}<a
							class="btn preset-tonal"
							href={changesHref(queue.detail.review.organisation_id ?? '')}
							>Continue to field changes →</a
						>{/if}
				{:else}<p>Select a staged record to review.</p>{/if}
			</section>
		</div>
	{/if}
</div>
