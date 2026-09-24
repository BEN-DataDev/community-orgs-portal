<script lang="ts">
	import { enhance } from '$app/forms';
	import { resolve } from '$app/paths';
	import type {
		validationQueueSchema,
		validationFilterInput,
		validationRunReadinessSchema
	} from '$lib/server/ingestion-review';
	import type { SubmitFunction } from '@sveltejs/kit';
	import type { z } from 'zod';
	let creatingRun = $state(false);

	let {
		queue,
		filter,
		readiness,
		form,
		campaign = ''
	}: {
		queue: z.infer<typeof validationQueueSchema>;
		filter: z.infer<typeof validationFilterInput>;
		readiness: z.infer<typeof validationRunReadinessSchema> | null;
		form: Record<string, unknown> | null | undefined;
		campaign?: string;
	} = $props();

	function issueHref(issue: string, offset = filter.offset) {
		const params = new URLSearchParams({ issue, issue_offset: String(offset) });
		if (filter.run) params.set('issue_run', filter.run);
		if (filter.release) params.set('release', filter.release);
		if (filter.category) params.set('category', filter.category);
		if (filter.decision) params.set('issue_decision', filter.decision);
		if (campaign) params.set('campaign', campaign);
		return `${resolve('/admin/ingestion/validation')}?${params}`;
	}
	function display(value: unknown) {
		return typeof value === 'string' ? value : JSON.stringify(value, null, 2);
	}
	function safeHttp(value: unknown) {
		if (typeof value !== 'string') return null;
		try {
			const url = new URL(value);
			return ['http:', 'https:'].includes(url.protocol) && !url.username && !url.password
				? url.href
				: null;
		} catch {
			return null;
		}
	}
	function decisionLabel(decision: string) {
		switch (decision) {
			case 'correct':
				return 'Resolved · Corrected';
			case 'omit':
				return 'Resolved · Omitted';
			case 'defer':
				return 'Deferred';
			case 'reject_record':
				return 'Resolved · Record rejected';
			default:
				return 'Unresolved';
		}
	}
	function decisionPreset(decision: string) {
		switch (decision) {
			case 'correct':
				return 'preset-tonal-success';
			case 'omit':
				return 'preset-tonal-surface';
			case 'defer':
				return 'preset-tonal-secondary';
			case 'reject_record':
				return 'preset-tonal-error';
			default:
				return 'preset-tonal-warning';
		}
	}
	const createCorrectedRun: SubmitFunction = ({ cancel }) => {
		if (creatingRun) {
			cancel();
			return;
		}
		creatingRun = true;
		return async ({ update }) => {
			try {
				await update();
			} finally {
				creatingRun = false;
			}
		};
	};
</script>

<section aria-labelledby="validation-heading" class="space-y-4">
	<header>
		<h2 id="validation-heading" class="text-xl font-bold">Validation issues</h2>
		<p class="text-sm">
			Resolve recoverable staged-data failures. This never changes the original evidence or
			publishes an organisation.
		</p>
	</header>
	<div class="grid gap-2 sm:grid-cols-5">
		<div class="card preset-tonal p-3">
			<strong>{queue.counts.total}</strong><span class="block text-sm">All issues</span>
		</div>
		<div class="card preset-tonal p-3">
			<strong>{queue.counts.blocking}</strong><span class="block text-sm">Blocking</span>
		</div>
		<div class="card preset-tonal p-3">
			<strong>{queue.counts.unresolved}</strong><span class="block text-sm">Unresolved</span>
		</div>
		<div class="card preset-tonal p-3">
			<strong>{queue.counts.deferred}</strong><span class="block text-sm">Deferred</span>
		</div>
		<div class="card preset-tonal p-3">
			<strong>{queue.counts.non_resolvable}</strong><span class="block text-sm">Non-resolvable</span
			>
		</div>
	</div>
	<form method="GET" class="card preset-tonal grid gap-3 p-4 md:grid-cols-4">
		<label class="label"
			>Run ID<input
				class="input"
				name="issue_run"
				value={filter.run}
				inputmode="numeric"
				pattern="[1-9][0-9]*"
			/></label
		>
		<label class="label"
			>Release ID<input
				class="input"
				name="release"
				value={filter.release}
				inputmode="numeric"
				pattern="[1-9][0-9]*"
			/></label
		>
		<label class="label"
			>Category<select class="select" name="category" value={filter.category}
				><option value="">All categories</option><option value="field_format">Field format</option
				><option value="missing_required_field">Missing required field</option><option
					value="duplicate_identity">Duplicate identity</option
				><option value="record_integrity">Record integrity</option><option value="record_scope"
					>Record scope</option
				><option value="source_schema">Source schema</option><option value="mapping_unknown"
					>Unknown mapping</option
				><option value="acquisition_error">Acquisition error</option><option
					value="licence_or_qualification">Licence or qualification</option
				></select
			></label
		>
		<label class="label"
			>Decision<select class="select" name="issue_decision" value={filter.decision}
				><option value="">All decisions</option><option value="unresolved">Unresolved</option
				><option value="correct">Corrected</option><option value="omit">Omitted</option><option
					value="defer">Deferred</option
				><option value="reject_record">Record rejected</option></select
			></label
		>
		<button class="btn preset-filled-primary-500 md:col-span-4">Filter issues</button>
	</form>
	<div class="grid gap-6 xl:grid-cols-[minmax(18rem,1fr)_2fr]">
		<div class="space-y-3">
			<p>{queue.total} matching issues.</p>
			<ul class="space-y-2">
				{#each queue.issues as issue}
					<li>
						<a
							class="card border-surface-200-800 hover:preset-tonal block border p-3"
							aria-current={queue.detail?.id === issue.id ? 'page' : undefined}
							href={issueHref(issue.id)}
							><span class="flex items-start justify-between gap-3"
								><strong class="min-w-0 break-words">{issue.code}</strong><span
									class={`badge shrink-0 ${decisionPreset(issue.decision)}`}
									>{decisionLabel(issue.decision)}</span
								></span
							><span class="block text-sm"
								>{issue.subject_native_id ?? `Row ${issue.source_row ?? 'unknown'}`}</span
							><span class="block text-sm">{issue.category} · {issue.severity}</span></a
						>
					</li>
				{/each}
			</ul>
			<nav aria-label="Validation issue pages" class="flex gap-4">
				{#if filter.offset > 0}<a
						class="anchor"
						href={issueHref('', Math.max(0, filter.offset - 50))}>Previous</a
					>{/if}
				{#if filter.offset + 50 < queue.total}<a
						class="anchor"
						href={issueHref('', filter.offset + 50)}>Next</a
					>{/if}
			</nav>
		</div>
		<div class="min-w-0 space-y-4">
			{#if queue.detail}
				{@const issue = queue.detail}
				<div class="card preset-tonal space-y-2 p-4">
					<div class="flex items-start justify-between gap-3">
						<h3 class="min-w-0 font-semibold break-words">{issue.code}</h3>
						<span
							class={`badge shrink-0 ${decisionPreset(issue.resolution?.decision ?? 'unresolved')}`}
							>{decisionLabel(issue.resolution?.decision ?? 'unresolved')}</span
						>
					</div>
					<p>{issue.detail}</p>
					<p class="text-sm">
						{issue.category} · {issue.severity} · validator {issue.validator_name}
						{issue.validator_version}
					</p>
					<p class="text-sm">
						Run {issue.run_id ?? '—'} · Release {issue.release_id ?? '—'} · Source record {issue.subject_native_id ??
							'—'} · Row {issue.source_row ?? '—'}
					</p>
					<p class="text-sm">
						Field: {issue.source_key ?? 'record-level'} → {issue.canonical_key ?? 'none'}
					</p>
					<pre class="max-h-60 overflow-auto text-xs break-all whitespace-pre-wrap">{display(
							issue.source_value
						)}</pre>
					{#if safeHttp(issue.source_value)}<a
							class="anchor"
							href={safeHttp(issue.source_value)!}
							target="_blank"
							rel="noopener noreferrer">Open HTTP(S) candidate</a
						>
						<p class="text-xs">
							Opening this URL does not validate ownership, relevance, or source identity.
						</p>{/if}
				</div>
				{#if issue.allowed_resolutions.includes('correct')}
					<form method="POST" use:enhance class="card border-surface-200-800 space-y-3 border p-4">
						<h3 class="font-semibold">Validate proposed value</h3>
						<input type="hidden" name="intent" value="validate_issue" /><input
							type="hidden"
							name="issue"
							value={issue.id}
						/>
						<label class="label"
							>Proposed value<input
								class="input"
								name="proposed"
								required
								maxlength="10000"
								value={typeof issue.resolution?.proposed_value === 'string'
									? issue.resolution.proposed_value
									: ''}
							/></label
						>
						<button class="btn preset-tonal">Validate proposed value</button>
						{#if form?.intent === 'validate_issue'}<p
								role="status"
								class:font-semibold={form.validationPassed}
							>
								{form.message as string}
							</p>{/if}
					</form>
				{/if}
				{#if issue.allowed_resolutions.length}
					<form method="POST" use:enhance class="card border-surface-200-800 space-y-3 border p-4">
						<h3 class="font-semibold">Record resolution</h3>
						<input type="hidden" name="intent" value="save_resolution" /><input
							type="hidden"
							name="issue"
							value={issue.id}
						/><input type="hidden" name="revision" value={issue.resolution?.revision ?? 0} />
						<label class="label"
							>Decision<select
								class="select"
								name="decision"
								required
								value={issue.resolution?.decision ?? ''}
								><option value="" disabled>Select a decision</option
								>{#each issue.allowed_resolutions as decision}<option value={decision}
										>{decision.replace('_', ' ')}</option
									>{/each}</select
							></label
						>
						{#if issue.allowed_resolutions.includes('correct')}<label class="label"
								>Corrected value<input
									class="input"
									name="proposed"
									maxlength="10000"
									value={typeof issue.resolution?.proposed_value === 'string'
										? issue.resolution.proposed_value
										: ''}
								/></label
							>{/if}
						<label class="label"
							>Decision note<textarea
								class="textarea"
								name="note"
								rows="3"
								required
								maxlength="2000"
								value={issue.resolution?.note ?? ''}
							></textarea></label
						>
						<label class="label"
							>Evidence reference (optional)<input
								class="input"
								name="evidence"
								maxlength="2000"
							/></label
						>
						<button class="btn preset-filled-primary-500">Save resolution</button>
						{#if form?.intent === 'save_resolution'}<p role="status">
								{form.message as string}
							</p>{/if}
					</form>
				{:else}<p class="card preset-tonal-error p-4">
						This failure is diagnostic only. It requires a new acquisition, mapping, schema, scope,
						or qualification decision and cannot be manually overridden.
					</p>{/if}
				{#if issue.run_id}
					<form
						method="POST"
						use:enhance={createCorrectedRun}
						class="card preset-tonal space-y-3 p-4"
						aria-busy={creatingRun}
					>
						<div class="flex items-start justify-between gap-3">
							<h3 class="font-semibold">Derived run</h3>
							{#if readiness?.active_replay}<span class="badge preset-tonal-primary shrink-0"
									>{readiness.active_replay.status === 'complete'
										? 'Complete'
										: readiness.active_replay.status === 'queued'
											? 'Queued'
											: 'Running'}</span
								>
							{:else if readiness?.eligible}<span class="badge preset-tonal-success shrink-0"
									>Ready</span
								>
							{:else}<span class="badge preset-tonal-warning shrink-0">Action required</span>{/if}
						</div>
						<p>
							The worker revalidates every retained record. The original run remains unchanged and
							the derived run remains ineligible for publication until ordinary identity and field
							review.
						</p>
						{#if readiness?.active_replay}<p role="status">
								{#if readiness.active_replay.status === 'complete'}Replay {readiness.active_replay
										.id}
									completed{#if readiness.active_replay.derived_run_id}
										as derived run {readiness.active_replay.derived_run_id}{/if}. Change a
									resolution before creating another corrected run.{:else}Replay {readiness
										.active_replay.id} is
									{readiness.active_replay.status}. Another replay cannot be queued yet.{/if}
							</p>
						{:else if readiness?.eligible}<p class="preset-tonal-success rounded-container p-3">
								All {readiness.blocking_count} blocking issues have replay-compatible decisions. This
								run is ready to queue.{#if readiness.rejected_blocking_count}
									{readiness.rejected_blocking_count} rejected record(s) will be intentionally excluded
									and retained in the replay audit evidence.{/if}
							</p>
						{:else if readiness}<div class="preset-tonal-warning rounded-container p-3">
								<p class="font-semibold">This run is not ready to queue.</p>
								<ul class="mt-2 list-disc space-y-1 pl-5 text-sm">
									{#if !readiness.raw_evidence_available}<li>Raw evidence has expired.</li>{/if}
									{#if readiness.issue_count === 0}<li>
											No validation issues exist for this run.
										</li>{/if}
									{#if readiness.acquisition_failure_count}<li>
											{readiness.acquisition_failure_count} acquisition failure(s) require a new acquisition.
										</li>{/if}
									{#if readiness.unresolved_blocking_count}<li>
											{readiness.unresolved_blocking_count} blocking issue(s) are unresolved.
										</li>{/if}
									{#if readiness.non_overridable_blocking_count}<li>
											{readiness.non_overridable_blocking_count} blocking issue(s) cannot be manually
											overridden.
										</li>{/if}
									{#if readiness.deferred_blocking_count}<li>
											{readiness.deferred_blocking_count} blocking issue(s) are deferred.
										</li>{/if}
								</ul>
							</div>
						{:else}<p class="preset-tonal-warning rounded-container p-3">
								Run readiness is unavailable. Reload before attempting to queue a corrected run.
							</p>{/if}
						<input type="hidden" name="intent" value="create_corrected_run" /><input
							type="hidden"
							name="run"
							value={issue.run_id}
						/><button
							class="btn preset-filled-primary-500"
							disabled={!readiness?.eligible || creatingRun}
							>{#if creatingRun}<span
									aria-hidden="true"
									class="size-4 animate-spin rounded-full border-2 border-current border-t-transparent"
								></span>Queuing corrected run…{:else}Create corrected run{/if}</button
						>
						{#if creatingRun}<p role="status" aria-live="polite">
								Submitting once. Do not refresh or click again; the request may commit even if the
								gateway times out.
							</p>{/if}
						{#if form?.intent === 'create_corrected_run'}<p role="status">
								{form.message as string}
							</p>{/if}
					</form>
				{/if}
				{#if issue.history.length}<details class="card preset-tonal p-4">
						<summary class="cursor-pointer font-semibold">Resolution history</summary>
						<ul class="mt-3 space-y-2">
							{#each issue.history as event}<li>
									Revision {event.revision}: {event.decision} · {event.resolved_at}<span
										class="block text-sm">{event.note}</span
									>
								</li>{/each}
						</ul>
					</details>{/if}
			{:else}<p>
					Select a validation issue to inspect its immutable evidence and permitted actions.
				</p>{/if}
		</div>
	</div>
</section>
