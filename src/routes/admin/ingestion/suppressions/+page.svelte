<script lang="ts">
	import { resolve } from '$app/paths';
	import QueueNavigation from '$components/ingestion/QueueNavigation.svelte';
	import WithdrawalControls from '$components/ingestion/WithdrawalControls.svelte';
	import type { PageProps } from './$types';
	let { data, form }: PageProps = $props();
	const queue = $derived(data.queue);
	function href(run: string, version?: string, offset = data.offset) {
		const params = new URLSearchParams({ run, offset: String(offset) });
		if (version) params.set('version', version);
		if (data.campaign) params.set('campaign', data.campaign);
		return `${resolve('/admin/ingestion/suppressions')}?${params}`;
	}
</script>

<svelte:head><title>Suppression and withdrawal queue</title></svelte:head>
<div class="space-y-6">
	<header class="space-y-2">
		<a class="anchor" href={resolve('/admin/ingestion')}>All ingestion queues</a>
		<h1 class="text-2xl font-bold">Suppression and withdrawal queue</h1>
		<p>Primary decision: submit exact content removal for independent review.</p>
		<p class="text-sm">
			Next responsible role: <strong>Data Steward</strong>, then a different authorised release
			approver.
		</p>
	</header>
	<QueueNavigation
		current="suppressions"
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
			<section aria-label="Suppression records" class="space-y-3">
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
							href={href(queue.run!, undefined, Math.max(0, data.offset - 50))}>Previous</a
						>{/if}{#if data.offset + 50 < queue.total}<a
							class="anchor"
							href={href(queue.run!, undefined, data.offset + 50)}>Next</a
						>{/if}
				</nav>
			</section>
			<section aria-label="Suppression decision" class="min-w-0 space-y-4">
				{#if queue.detail}<h2 class="text-xl font-bold">Source record {queue.detail.native_id}</h2>
					{#if data.withdrawal}<WithdrawalControls
							run={queue.run!}
							version={queue.detail.id}
							status={data.withdrawal}
							fields={data.withdrawalFields}
						/>{/if}{:else}<p>Select a staged record.</p>{/if}
			</section>
		</div>{:else}<p>No staged runs are available.</p>{/if}
</div>
