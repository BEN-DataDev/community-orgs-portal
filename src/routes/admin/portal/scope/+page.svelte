<script lang="ts">
	import { resolve } from '$app/paths';
	import { enhance } from '$app/forms';
	import type { PageProps } from './$types';
	let { data, form }: PageProps = $props();
	const current = $derived(data.revisions.find((item) => item.current));
</script>

<svelte:head><title>Portal scope</title></svelte:head>
<div class="space-y-6">
	<header class="space-y-2">
		<a class="anchor" href={resolve('/admin')}>Back to Admin</a>
		<h1 class="text-2xl font-bold">Portal scope</h1>
		<p>
			Postcodes are the authoritative discovery boundary. Creating a revision does not discover,
			publish or remove organisations.
		</p>
	</header>
	{#if form?.message}<p role="status" class="card preset-tonal p-4">{form.message}</p>{/if}
	{#if current}
		<section class="card border-surface-200-800 space-y-3 border p-5">
			<h2 class="text-xl font-semibold">Current revision {current.revision}</h2>
			<p>{current.postcodes.join(', ')}</p>
			<p>Policy: {current.inclusion_policy_version}</p>
			<p>{current.reason}</p>
		</section>
	{/if}
	<section class="card border-surface-200-800 space-y-4 border p-5">
		<h2 class="text-xl font-semibold">Create scope revision</h2>
		<p>Saving is append-only and cancels queued or running acquisitions tied to the old scope.</p>
		<form method="POST" use:enhance class="space-y-4">
			<input type="hidden" name="expectedRevision" value={data.configuration_revision} />
			<label class="label">
				<span class="label-text">Postcodes (one per line)</span>
				<textarea class="textarea" name="postcodes" rows="12" required
					>{current?.postcodes.join('\n') ?? ''}</textarea
				>
			</label>
			<label class="label">
				<span class="label-text">Inclusion policy version</span>
				<input
					class="input"
					name="inclusionPolicyVersion"
					required
					maxlength="200"
					value={current?.inclusion_policy_version ?? ''}
				/>
			</label>
			<label class="label">
				<span class="label-text">Impact assessment</span>
				<textarea class="textarea" name="impactAssessment" rows="4" required maxlength="4000"
				></textarea>
			</label>
			<label class="label">
				<span class="label-text">Approval reason</span>
				<textarea class="textarea" name="reason" rows="3" required maxlength="2000"></textarea>
			</label>
			<label class="flex items-center gap-2">
				<input class="checkbox" type="checkbox" name="requiresRebaseline" checked />
				<span>A scope re-baseline campaign is required</span>
			</label>
			<button class="btn preset-filled-primary-500">Create immutable revision</button>
		</form>
	</section>
	<section class="space-y-3">
		<h2 class="text-xl font-semibold">Revision history</h2>
		{#each data.revisions as item (item.id)}
			<article class="card border-surface-200-800 space-y-2 border p-4">
				<h3 class="font-semibold">Revision {item.revision}{item.current ? ' · current' : ''}</h3>
				<p>{item.postcodes.join(', ')}</p>
				<p>{item.reason}</p>
				<p>Impact: {item.impact_assessment}</p>
				<p>Re-baseline required: {item.requires_rebaseline ? 'yes' : 'no'}</p>
				<p>Approved: {item.approved_at}</p>
			</article>
		{:else}<p>No authoritative scope has been configured.</p>{/each}
	</section>
</div>
