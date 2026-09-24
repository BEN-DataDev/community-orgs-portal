<script lang="ts">
	import { enhance } from '$app/forms';
	import { resolve } from '$app/paths';
	import FieldGroups from '$components/ingestion/FieldGroups.svelte';
	import QueueNavigation from '$components/ingestion/QueueNavigation.svelte';
	import SavedApprovals from '$components/ingestion/SavedApprovals.svelte';
	import type { PageProps } from './$types';
	let { data, form }: PageProps = $props();
	const queue = $derived(data.queue);
	function href(run: string, version?: string, target?: string, offset = data.offset) {
		const params = new URLSearchParams({ run, offset: String(offset) });
		if (version) params.set('version', version);
		if (target !== undefined) params.set('target', target);
		if (data.campaign) params.set('campaign', data.campaign);
		return `${resolve('/admin/ingestion/changes')}?${params}`;
	}
</script>

<svelte:head><title>Field-change queue</title></svelte:head>
<div class="space-y-6">
	<header class="space-y-2">
		<a class="anchor" href={resolve('/admin/ingestion')}>All ingestion queues</a>
		<h1 class="text-2xl font-bold">Field-change queue</h1>
		<p>Primary decision: approve exact eligible field changes for a reviewed identity.</p>
		<p class="text-sm">
			Next responsible role: <strong>Data Steward</strong>. Approval and release submission do not
			publish changes.
		</p>
	</header>
	<QueueNavigation
		current="changes"
		campaign={data.campaign}
		run={queue.run ?? ''}
		version={queue.detail?.id ?? ''}
	/>
	{#if form?.message}<p role="status" class="card preset-tonal p-4">{form.message}</p>{/if}
	<form method="GET" class="flex flex-wrap items-end gap-3">
		{#if data.campaign}<input type="hidden" name="campaign" value={data.campaign} />{/if}<label
			class="label flex-1"
			>Import run<select class="select" name="run" value={queue.run ?? ''} required
				>{#each queue.runs as run}<option value={run.id}
						>Run {run.id} · {run.run_key} · {run.completion}</option
					>{/each}</select
			></label
		><button class="btn preset-filled-primary-500" disabled={!queue.runs.length}>Open run</button>
	</form>
	{#if queue.runs.length}<div class="grid gap-6 xl:grid-cols-[minmax(16rem,1fr)_2fr]">
			<section aria-label="Field-change records" class="space-y-3">
				<p>{queue.total} staged records.</p>
				<ul class="space-y-2">
					{#each queue.records as record}<li>
							<a
								class="card border-surface-200-800 hover:preset-tonal block border p-3"
								href={href(queue.run!, record.id)}
								aria-current={queue.detail?.id === record.id ? 'page' : undefined}
								><strong>{record.name}</strong><span class="block text-sm">{record.decision}</span
								></a
							>
						</li>{/each}
				</ul>
				<nav class="flex gap-4" aria-label="Record pages">
					{#if data.offset > 0}<a
							class="anchor"
							href={href(queue.run!, undefined, undefined, Math.max(0, data.offset - 50))}
							>Previous</a
						>{/if}{#if data.offset + 50 < queue.total}<a
							class="anchor"
							href={href(queue.run!, undefined, undefined, data.offset + 50)}>Next</a
						>{/if}
				</nav>
			</section>
			<section aria-label="Field-change decision" class="min-w-0 space-y-4">
				{#if queue.detail}<h2 class="text-xl font-bold">Source record {queue.detail.native_id}</h2>
					{#if !queue.detail.review || !['link', 'create'].includes(queue.detail.review.decision)}<div
							class="card preset-tonal-warning p-4"
						>
							Identity decision required. <a
								class="anchor"
								href={`${resolve('/admin/ingestion/identity')}?${new URLSearchParams({ run: queue.run!, version: queue.detail.id, ...(data.campaign ? { campaign: data.campaign } : {}) })}`}
								>Open identity queue</a
							>.
						</div>{/if}{#if data.preview}<p>
							Comparing with <strong
								>{data.preview.organisation_name ?? 'a proposed new organisation'}</strong
							>.
						</p>
						<a class="anchor" href={href(queue.run!, queue.detail.id, '')}
							>Compare as a new organisation</a
						><FieldGroups
							fields={data.preview.fields}
						/>{#if queue.detail.review && ['link', 'create'].includes(queue.detail.review.decision) && data.preview.organisation_id === queue.detail.review.organisation_id}<form
								method="POST"
								use:enhance
								class="card preset-tonal space-y-3 p-4"
							>
								<h3 class="font-semibold">Approve selected fields</h3>
								<input type="hidden" name="intent" value="approve" /><input
									type="hidden"
									name="run"
									value={queue.run!}
								/><input type="hidden" name="version" value={queue.detail.id} /><input
									type="hidden"
									name="revision"
									value={queue.detail.review.revision}
								/><input
									type="hidden"
									name="organisation"
									value={data.preview.organisation_id ?? ''}
								/><FieldGroups fields={data.preview.fields} selectable /><button
									class="btn preset-filled-primary-500">Save field approval</button
								>
							</form>{/if}{/if}{#if data.approvals.length}<SavedApprovals
							approvals={data.approvals}
							savedApprovalId={form && 'approvalId' in form ? form.approvalId : null}
							message={form?.message}
						/>{/if}{:else}<p>Select a staged record.</p>{/if}
			</section>
		</div>{:else}<p>No staged runs are available.</p>{/if}
</div>
