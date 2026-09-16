<script lang="ts">
	import { resolve } from '$app/paths';
	import { enhance } from '$app/forms';
	import type { PageProps } from './$types';
	let { data, form }: PageProps = $props();
	const returnHref = $derived(
		`${resolve('/admin/ingestion')}?${new URLSearchParams({ ...(data.run ? { run: data.run } : {}), ...(data.version ? { version: data.version } : {}) })}`
	);
</script>

<svelte:head><title>Source approvals</title></svelte:head>
<div class="space-y-6">
	<header class="space-y-2">
		<a class="anchor" href={resolve('/admin')}>Back to Admin</a>
		<h1 class="text-2xl font-bold">Source approvals</h1>
		<p>Review the source evidence and licence before enabling a source.</p>
		<p>
			Enabling applies to the entire source/resource: it allows staging, field approvals and
			publication from complete imports. Each organisation still requires review, field approval and
			publication. Incomplete imports remain blocked.
		</p>
		<p>Pausing blocks future operations; it does not withdraw already published organisations.</p>
		<a class="anchor" href={returnHref}>Return to import review</a>
	</header>
	{#if form?.message}<p role="status" class="card preset-tonal p-4">{form.message}</p>{/if}
	{#each data.sources as source}
		<section class="card border-surface-200-800 space-y-4 border p-5">
			<h2 class="text-xl font-semibold">
				{typeof source.metadata.public_title === 'string'
					? source.metadata.public_title
					: source.source_id}
			</h2>
			<p class="break-all">Source: {source.source_id} · Resource: {source.resource_id}</p>
			<p>Status: <strong>{source.enabled ? 'Enabled' : 'Paused'}</strong></p>
			{#if source.metadata.synthetic}<p>Synthetic test data — not a live public source.</p>{/if}
			{#if source.url}<a class="anchor" href={source.url} target="_blank" rel="noreferrer"
					>View source dataset</a
				>{/if}
			<p>
				Licence: {typeof source.metadata.public_licence === 'string'
					? source.metadata.public_licence
					: 'Not recorded'}
			</p>
			{#if source.licenceUrl}<a
					class="anchor"
					href={source.licenceUrl}
					target="_blank"
					rel="noreferrer">View licence</a
				>{/if}
			<details>
				<summary class="cursor-pointer font-semibold"
					>Acquisition evidence (recorded at staging)</summary
				>
				<pre class="overflow-x-auto text-sm break-all whitespace-pre-wrap">{JSON.stringify(
						source.metadata,
						null,
						2
					)}</pre>
			</details>
			<h3 class="font-semibold">Recent imports</h3>
			<ul class="space-y-2">
				{#each source.runs as run}<li>
						<a
							class="anchor"
							href={`${resolve('/admin/ingestion')}?${new URLSearchParams({ run: run.id, ...(run.id === data.run && data.version ? { version: data.version } : {}) })}`}
							>{run.run_key}</a
						>
						· <strong>{run.completion}</strong> · {run.observed_at}{#if run.id === data.run}
							· Selected import{/if}
					</li>{:else}<li>No imports staged yet.</li>{/each}
			</ul>
			{#key source.token}
				<form method="POST" use:enhance class="space-y-3">
					<input type="hidden" name="source" value={source.source_id} /><input
						type="hidden"
						name="resource"
						value={source.resource_id}
					/><input type="hidden" name="token" value={source.token} /><input
						type="hidden"
						name="enabled"
						value={String(!source.enabled)}
					/>
					<label class="label"
						>Reason<textarea class="textarea" name="reason" required maxlength="2000" rows="2"
						></textarea></label
					>
					<label class="flex items-start gap-2"
						><input class="checkbox" type="checkbox" name="confirm" value="yes" required /><span
							>{source.enabled
								? 'I confirm that this source/resource should be paused.'
								: 'I have reviewed the source evidence, licence and scope and approve enabling this source/resource.'}</span
						></label
					>
					<button class="btn preset-filled-primary-500"
						>{source.enabled ? 'Pause source' : 'Approve and enable source'}</button
					>
				</form>
			{/key}
			{#if source.history.length}<details>
					<summary class="cursor-pointer font-semibold">Recent status changes</summary>
					<ul class="space-y-2">
						{#each source.history as event}<li>
								{event.changed_at} · {event.enabled ? 'Enabled' : 'Paused'} · {event.reason} · Admin {event.changed_by}
							</li>{/each}
					</ul>
				</details>{/if}
		</section>
	{:else}<p>No sources are configured.</p>{/each}
</div>
