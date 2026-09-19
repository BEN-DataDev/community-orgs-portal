<script lang="ts">
	import { resolve } from '$app/paths';
	import { enhance } from '$app/forms';
	import { invalidateAll } from '$app/navigation';
	import type { PageProps } from './$types';
	let { data, form }: PageProps = $props();
</script>

<svelte:head><title>Acquisition jobs</title></svelte:head>
<div class="space-y-6">
	<header class="space-y-2">
		<a class="anchor" href={resolve('/admin/ingestion')}>Back to import review</a>
		<h1 class="text-2xl font-bold">Acquisition jobs</h1>
		<p>
			Fetch up to 1,000 ACNC records for a postcode cohort into private staging. Completed imports
			require review and approval before publication.
		</p>
		<p>
			Scheduled jobs run when the daily scheduler next checks for due work. A connected acquisition
			worker is required to process queued jobs.
		</p>
		<button type="button" class="btn preset-tonal" onclick={() => invalidateAll()}
			>Refresh status</button
		>
		{#if data.canConfigure}<a class="anchor" href={resolve('/admin/sources')}
				>Manage source approvals</a
			>{/if}
	</header>
	{#if form?.message}<p role="status" class="card preset-tonal p-4">{form.message}</p>{/if}
	{#each data.sources as source (source.resource_id)}
		<section class="card border-surface-200-800 space-y-4 border p-5">
			<h2 class="text-xl font-semibold">{source.title}</h2>
			<p class="break-all">Resource: {source.resource_id}</p>
			<p>
				Source {source.enabled ? 'enabled' : 'paused'} · Postcodes {source.postcodes?.join(', ') ??
					'not configured'}
			</p>
			<p>
				Schedule: {source.interval_hours
					? `every ${source.interval_hours / 24} days`
					: 'off'}{#if source.next_due_at}
					· Next due: {source.next_due_at}{/if}
			</p>
			<form method="POST" action="?/run" use:enhance>
				<input type="hidden" name="resource" value={source.resource_id} />
				<button
					class="btn preset-filled-primary-500"
					disabled={!source.enabled || !source.postcodes?.length}>Run acquisition</button
				>
			</form>
			{#if data.canConfigure}
				<details>
					<summary class="cursor-pointer font-semibold">Configure acquisition</summary>
					<p class="my-3">
						Saving cancels active jobs for this resource. Confirm the licence title against the
						source evidence before saving.
					</p>
					{#key source.revision}
						<form method="POST" action="?/configure" use:enhance class="space-y-3">
							<input type="hidden" name="resource" value={source.resource_id} />
							<input type="hidden" name="revision" value={source.revision} />
							<label class="label"
								>Postcodes (one per line)<textarea
									class="input"
									name="postcodes"
									rows="5"
									required
									maxlength="249">{source.postcodes?.join('\n') ?? ''}</textarea
								></label
							>
							<label class="label"
								>Reviewed licence title<input
									class="input"
									name="licence"
									value={source.licence_title}
									required
									maxlength="300"
								/></label
							>
							<label class="label"
								>Schedule<select
									class="select"
									name="interval"
									value={source.interval_hours?.toString() ?? 'off'}
								>
									<option value="off">Off — manual acquisition only</option><option value="24"
										>Daily</option
									><option value="168">Every 7 days</option><option value="720"
										>Every 30 days</option
									>
								</select></label
							>
							<button class="btn preset-tonal">Save configuration</button>
						</form>
					{/key}
				</details>
			{/if}
		</section>
	{:else}<p>No live ACNC resources are registered.</p>{/each}
	<section class="space-y-3">
		<h2 class="text-xl font-semibold">Recent jobs</h2>
		<p>
			Latest 50 jobs. Source pauses block work; expired worker leases are recovered on the next
			worker check.
		</p>
		{#each data.jobs as job (job.id)}
			<article class="card border-surface-200-800 space-y-2 border p-4">
				<p><strong>{job.status}</strong> · {job.origin} · Attempt {job.attempts} of 3</p>
				<p class="break-all">Job {job.id} · Resource {job.resource_id}</p>
				<p>Queued: {job.created_at}</p>
				{#if job.status === 'queued'}<p>Available: {job.available_at}</p>{/if}
				{#if job.status === 'running'}<p>Worker lease ends: {job.lease_until}</p>{/if}
				{#if job.acquired}<p>Acquisition evidence saved.</p>{/if}
				{#if job.message}<p>{job.message}</p>{/if}
				{#if job.run_id}<a class="anchor" href={resolve('/admin/ingestion') + `?run=${job.run_id}`}
						>Review import</a
					>{/if}
			</article>
		{:else}<p>No acquisition jobs yet.</p>{/each}
	</section>
</div>
