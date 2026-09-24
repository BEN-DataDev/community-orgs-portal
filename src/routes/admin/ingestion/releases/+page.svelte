<script lang="ts">
	import { enhance } from '$app/forms';
	import { resolve } from '$app/paths';
	import QueueNavigation from '$components/ingestion/QueueNavigation.svelte';
	import type { PageProps } from './$types';
	let { data, form }: PageProps = $props();

	const labels: Record<string, string> = {
		initial_seed: 'Initial seed',
		ordinary_update: 'Ordinary update',
		suppression: 'Suppression',
		destructive: 'Destructive'
	};

	function itemLabel(item: Record<string, unknown>) {
		return item.action === 'publish_change_set'
			? `Publish change set ${item.change_set_id}`
			: `Suppress ${item.field} from run ${item.run}, version ${item.version}`;
	}
</script>

<svelte:head><title>Publication releases</title></svelte:head>
<div class="space-y-6">
	<header class="space-y-2">
		<a class="anchor" href={resolve('/admin')}>Back to Admin</a>
		{#if data.canSteward}<a class="anchor" href={resolve('/admin/ingestion')}>Ingestion queues</a
			>{/if}
		<h1 class="text-2xl font-bold">Publication releases</h1>
		<p>
			Approve and publish frozen release revisions. Initial and destructive work always requires a
			different person.
		</p>
	</header>
	<QueueNavigation current="releases" campaign={data.campaign} />
	{#if form?.message}<p role="status" class="card preset-tonal p-4">{form.message}</p>{/if}

	<section
		class="card border-surface-200-800 space-y-3 border p-4"
		aria-labelledby="approval-policy"
	>
		<h2 id="approval-policy" class="text-lg font-semibold">Ordinary update policy</h2>
		<p>
			Revision {data.queue.policy.revision} · {data.queue.policy
				.ordinary_requires_independent_approval
				? 'Two-person approval'
				: 'One-person approval'}
		</p>
		<p class="text-sm">{data.queue.policy.reason} · {data.queue.policy.updated_at}</p>
		{#if data.canAdmin}
			<form method="POST" use:enhance class="space-y-3">
				<input type="hidden" name="intent" value="policy" />
				<input type="hidden" name="revision" value={data.queue.policy.revision} />
				<label class="label"
					>Required approval<select
						class="select"
						name="ordinaryApproval"
						required
						value={data.queue.policy.ordinary_requires_independent_approval
							? 'two_person'
							: 'one_person'}
						><option value="one_person">Submitter only</option><option value="two_person"
							>Independent approver</option
						></select
					></label
				>
				<label class="label"
					>Policy reason<textarea class="textarea" name="reason" required maxlength="2000" rows="2"
					></textarea></label
				>
				<button class="btn preset-filled-primary-500">Update policy</button>
			</form>
		{/if}
	</section>

	<section class="space-y-4" aria-labelledby="release-queue">
		<h2 id="release-queue" class="text-xl font-semibold">Release queue</h2>
		{#each data.queue.releases as release (release.release_id)}
			<article class="card border-surface-200-800 space-y-3 border p-4">
				<header class="flex flex-wrap items-center justify-between gap-2">
					<h3 class="font-semibold">
						{labels[release.release_class]} · revision {release.revision}
					</h3>
					<span class="badge preset-tonal">{release.status}</span>
				</header>
				<p>{release.reason}</p>
				<p class="text-sm break-all">
					Release {release.release_id} · submitted {release.submitted_at} by {release.submitted_by}
				</p>
				<p class="text-sm break-all">Frozen SHA-256: {release.content_sha256}</p>
				<ul class="list-disc space-y-1 pl-5">
					{#each release.items as item}<li>{itemLabel(item)}</li>{/each}
				</ul>
				{#each release.decisions as decision}
					<p class="text-sm">
						{decision.decision} by {decision.decided_by} · {decision.decided_at} · {decision.note}
					</p>
				{/each}
				{#if release.can_decide}
					<form method="POST" use:enhance class="space-y-3">
						<input type="hidden" name="intent" value="decision" />
						<input type="hidden" name="release" value={release.release_id} />
						<input type="hidden" name="revision" value={release.revision} />
						<label class="label"
							>Decision<select class="select" name="decision" required
								><option value="approved">Approve exact revision</option><option value="rejected"
									>Reject</option
								></select
							></label
						>
						<label class="label"
							>Decision note<textarea
								class="textarea"
								name="note"
								required
								maxlength="2000"
								rows="2"
							></textarea></label
						>
						<button class="btn preset-filled-primary-500">Record decision</button>
					</form>
				{/if}
				{#if release.can_publish}
					<form method="POST" use:enhance>
						<input type="hidden" name="intent" value="publish" />
						<input type="hidden" name="release" value={release.release_id} />
						<input type="hidden" name="revision" value={release.revision} />
						<button class="btn preset-filled-success-500">Publish exact approved revision</button>
					</form>
				{/if}
			</article>
		{:else}
			<p>No publication releases have been submitted.</p>
		{/each}
	</section>
</div>
