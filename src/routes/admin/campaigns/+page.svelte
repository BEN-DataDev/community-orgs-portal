<script lang="ts">
	import { resolve } from '$app/paths';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const typeLabels: Record<string, string> = {
		initial_seed: 'Initial seed',
		scheduled_refresh: 'Scheduled refresh',
		scope_rebaseline: 'Scope re-baseline',
		correction: 'Correction',
		withdrawal: 'Withdrawal',
		source_reprocessing: 'Source reprocessing'
	};
	const stateLabels: Record<string, string> = {
		blocked: 'Blocked',
		ready_for_release: 'Ready for release',
		release_in_progress: 'Release in progress',
		published: 'Published'
	};
	const statePreset: Record<string, string> = {
		blocked: 'preset-tonal-error',
		ready_for_release: 'preset-tonal-success',
		release_in_progress: 'preset-tonal-warning',
		published: 'preset-filled-success-500'
	};
	const roleLabels: Record<string, string> = {
		data_steward: 'Data Steward',
		portal_administrator: 'Portal Administrator'
	};
	type QueuePath =
		| '/admin/ingestion/validation'
		| '/admin/ingestion/identity'
		| '/admin/ingestion/changes'
		| '/admin/ingestion/releases'
		| '/admin/ingestion/suppressions';
	function queueHref(path: QueuePath, campaign: (typeof data.campaigns)[number]) {
		const params = new URLSearchParams({ campaign: campaign.campaign_id });
		const run = campaign.artifacts.find((artifact) => artifact.kind === 'ingestion_run');
		if (run) {
			if (path.endsWith('/validation')) params.set('issue_run', run.artifact_key);
			else params.set('run', run.artifact_key);
		}
		return `${resolve(path)}?${params}`;
	}
</script>

<svelte:head><title>Campaigns</title></svelte:head>

<div class="space-y-6">
	<header class="space-y-2">
		<a class="anchor" href={resolve('/admin')}>Back to Admin</a>
		<h1 class="text-2xl font-bold">Campaigns</h1>
		<p class="text-surface-600-400">
			Track each establishment, refresh or corrective operation against its frozen scope, source,
			mapping and approval-policy references.
		</p>
	</header>

	<nav aria-label="Campaign work queues" class="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
		<a class="card preset-tonal p-4" href={resolve('/admin/ingestion/validation')}>Validation</a>
		<a class="card preset-tonal p-4" href={resolve('/admin/ingestion/identity')}
			>Identity and eligibility</a
		>
		<a class="card preset-tonal p-4" href={resolve('/admin/ingestion/changes')}>Field changes</a>
		<a class="card preset-tonal p-4" href={resolve('/admin/ingestion/releases')}
			>Publication releases</a
		>
		<a class="card preset-tonal p-4" href={resolve('/admin/ingestion/suppressions')}
			>Suppression and withdrawal</a
		>
	</nav>

	<section class="space-y-4" aria-labelledby="campaign-list">
		<h2 id="campaign-list" class="text-xl font-semibold">Campaign progress</h2>
		{#each data.campaigns as campaign (campaign.campaign_id)}
			<article class="card preset-outlined space-y-5 p-5">
				<header class="flex flex-wrap items-start justify-between gap-3">
					<div>
						<p class="text-surface-600-400 text-sm">{typeLabels[campaign.campaign_type]}</p>
						<h3 class="text-lg font-semibold">{campaign.name}</h3>
						<p class="text-surface-600-400 mt-1 text-sm">
							Scope revision {campaign.scope_revision} · inclusion {campaign.inclusion_policy_version}
							· approval policy {campaign.approval_policy_revision}
						</p>
					</div>
					<span class={`badge ${statePreset[campaign.readiness.state]}`}>
						{stateLabels[campaign.readiness.state]}
					</span>
				</header>
				<nav aria-label={`Queues for ${campaign.name}`} class="flex flex-wrap gap-3 text-sm">
					<a class="anchor" href={queueHref('/admin/ingestion/validation', campaign)}>Validation</a>
					<a class="anchor" href={queueHref('/admin/ingestion/identity', campaign)}>Identity</a>
					<a class="anchor" href={queueHref('/admin/ingestion/changes', campaign)}>Field changes</a>
					<a class="anchor" href={queueHref('/admin/ingestion/releases', campaign)}>Releases</a>
					<a class="anchor" href={queueHref('/admin/ingestion/suppressions', campaign)}
						>Suppression</a
					>
				</nav>

				<dl class="grid gap-3 sm:grid-cols-3 xl:grid-cols-6">
					<div>
						<dt class="text-sm">Source records</dt>
						<dd class="text-xl font-semibold">{campaign.readiness.counts.records}</dd>
					</div>
					<div>
						<dt class="text-sm">Artifacts</dt>
						<dd class="text-xl font-semibold">{campaign.readiness.counts.artifacts}</dd>
					</div>
					<div>
						<dt class="text-sm">Validation blockers</dt>
						<dd class="text-xl font-semibold">{campaign.readiness.counts.validation_blockers}</dd>
					</div>
					<div>
						<dt class="text-sm">Identity pending</dt>
						<dd class="text-xl font-semibold">{campaign.readiness.counts.identity_pending}</dd>
					</div>
					<div>
						<dt class="text-sm">Field decisions</dt>
						<dd class="text-xl font-semibold">{campaign.readiness.counts.field_changes_pending}</dd>
					</div>
					<div>
						<dt class="text-sm">Releases</dt>
						<dd class="text-xl font-semibold">
							{campaign.readiness.counts.published_releases}/{campaign.readiness.counts.releases}
						</dd>
					</div>
				</dl>

				{#if campaign.readiness.blockers.length}
					<div class="space-y-2">
						<h4 class="font-semibold">Next blockers</h4>
						<ul class="space-y-2">
							{#each campaign.readiness.blockers as blocker}
								<li
									class="preset-tonal-error rounded-base flex flex-wrap justify-between gap-2 p-3"
								>
									<span>{blocker.message}</span>
									<span class="font-medium"
										>{roleLabels[blocker.responsible_role] ?? blocker.responsible_role}</span
									>
								</li>
							{/each}
						</ul>
					</div>
				{:else}
					<p class="preset-tonal-success rounded-base p-3">
						All source, validation, identity and field-decision gates are ready.
					</p>
				{/if}

				<details>
					<summary class="cursor-pointer font-medium">Pinned contract and evidence</summary>
					<div class="mt-3 space-y-3 text-sm">
						<p>{campaign.reason}</p>
						<p>
							Mapping versions:
							{Object.entries(campaign.mapping_versions)
								.map(([key, value]) => `${key}: ${value}`)
								.join(', ')}
						</p>
						<ul class="list-disc space-y-1 pl-5">
							{#each campaign.artifacts as artifact}
								<li>
									{artifact.purpose}: {artifact.source_id}/{artifact.resource_id} · {artifact.kind}
									{artifact.artifact_key} · parser {artifact.parser_version}
								</li>
							{/each}
						</ul>
						<p class="break-all">Campaign {campaign.campaign_id}</p>
					</div>
				</details>
			</article>
		{:else}
			<div class="card preset-tonal p-5">
				<h3 class="font-semibold">No campaigns yet</h3>
				<p>
					Create the first campaign through the campaign RPC after its source artifacts are staged.
				</p>
			</div>
		{/each}
	</section>
</div>
