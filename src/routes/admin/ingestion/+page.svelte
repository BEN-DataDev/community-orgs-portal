<script lang="ts">
	import FieldGroups from '../../../components/ingestion/FieldGroups.svelte';
	import WithdrawalControls from '$components/ingestion/WithdrawalControls.svelte';
	import { resolve } from '$app/paths';
	import { enhance } from '$app/forms';
	import type { PageProps } from './$types';
	let { data, form }: PageProps = $props();
	const queue = $derived(data.queue);
	function previewHref(target: string) {
		const params = new URLSearchParams({
			run: queue.run!,
			version: queue.detail!.id,
			target,
			offset: String(data.offset),
			search: data.search
		});
		return `${resolve('/admin/ingestion')}?${params}`;
	}
	function display(value: unknown) {
		return value == null ? '—' : typeof value === 'string' ? value : JSON.stringify(value);
	}

	function href(run: string, version?: string, offset = 0) {
		const params = new URLSearchParams({ run, offset: String(offset) });
		if (version) params.set('version', version);
		return `${resolve('/admin/ingestion')}?${params}`;
	}
</script>

<svelte:head><title>Import review</title></svelte:head>
<div class="space-y-6">
	<header>
		<a class="anchor" href={resolve('/admin')}>Back to Admin</a>
		<h1 class="text-2xl font-bold">Import review</h1>
		<p>Compare source evidence with existing organisations and record a proposed decision.</p>
		<p class="text-sm">
			Saving a review does not publish or change an organisation. Shared ABNs and names require
			identity and branch checks.
		</p>
	</header>
	{#if form?.message}<p role="status" class="card preset-tonal p-4">{form.message}</p>{/if}
	<form method="GET" class="flex flex-wrap items-end gap-3">
		<label class="label flex-1"
			>Import run<select class="select" name="run" value={queue.run ?? ''} required>
				{#each queue.runs as run}<option value={run.id}
						>{run.run_key} · {run.completion} · {run.observed_at}</option
					>{/each}
			</select></label
		><button class="btn preset-filled-primary-500" disabled={!queue.runs.length}>Open run</button>
	</form>
	{#if !queue.runs.length}<p>No staged runs are available.</p>{:else}
		{@const selectedRun = queue.runs.find((r) => r.id === queue.run)}
		{#if selectedRun}<p class="text-sm">
				Source: {selectedRun.source_id} · Resource: {selectedRun.resource_id} · Completion:
				<strong>{selectedRun.completion}</strong>
			</p>{/if}
		<p>{queue.total} staged records. Partial and failed runs remain evidence only.</p>
		<div class="grid gap-6 xl:grid-cols-[minmax(16rem,1fr)_2fr]">
			<section aria-label="Staged records" class="space-y-3">
				<ul class="space-y-2">
					{#each queue.records as record}<li>
							<a
								class="card border-surface-200-800 hover:preset-tonal block border p-3"
								href={href(queue.run!, record.id, data.offset)}
								aria-current={queue.detail?.id === record.id ? 'page' : undefined}
								><span class="font-semibold">{record.name}</span><span class="block text-sm"
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
			<section aria-label="Record review" class="min-w-0 space-y-5">
				{#if queue.detail}
					{#key `${queue.run}:${queue.detail.id}:${queue.detail.review?.revision ?? 0}`}
						<h2 class="text-xl font-bold">Source record {queue.detail.native_id}</h2>
						<div class="overflow-x-auto">
							<table class="w-full text-left text-sm">
								<caption class="pb-2 text-left font-semibold">Source values</caption><thead
									><tr><th class="p-2">Field</th><th class="p-2">Value</th></tr></thead
								><tbody
									>{#each queue.detail.payload.assertions as assertion}<tr
											class="border-surface-200-800 border-t"
											><th scope="row" class="p-2">{assertion.field}</th><td class="p-2 break-all"
												>{typeof assertion.value === 'string'
													? assertion.value
													: JSON.stringify(assertion.value)}</td
											></tr
										>{/each}</tbody
								>
							</table>
						</div>
						<details class="card preset-tonal p-4">
							<summary class="cursor-pointer font-semibold">Source values and provenance</summary>
							<pre
								class="mt-3 max-h-96 overflow-auto text-xs break-all whitespace-pre-wrap">{JSON.stringify(
									queue.detail.payload,
									null,
									2
								)}</pre>
						</details>
						<form method="GET" class="flex flex-wrap items-end gap-3">
							<input type="hidden" name="run" value={queue.run!} /><input
								type="hidden"
								name="version"
								value={queue.detail.id}
							/><input type="hidden" name="offset" value={data.offset} />
							<label class="label flex-1"
								>Find an organisation by name<input
									class="input"
									name="search"
									value={data.search}
									minlength="2"
									maxlength="100"
								/></label
							><button class="btn preset-tonal">Search</button>
						</form>
						<h3 class="font-semibold">Possible matches</h3>
						{#each queue.candidates as candidate}<article
								class="card border-surface-200-800 border p-4"
							>
								<h4 class="font-semibold">{candidate.entity_name}</h4>
								<a class="anchor" href={previewHref(candidate.org_id)}>Compare fields</a>
								<p>{candidate.reason}</p>
								<p class="text-sm">
									ABN: {candidate.abn ?? 'None'} · {candidate.physical_address ??
										candidate.postal_address ??
										'No address'}
								</p>
								<p class="text-sm break-all">{candidate.website ?? 'No website'}</p>
								<a class="anchor" href={resolve('/organisations/[id]', { id: candidate.org_id })}
									>View organisation</a
								>
							</article>{:else}<p>
								No candidates found. Try a broader name search before proposing a new organisation.
							</p>{/each}
						{#if data.preview}
							<section aria-label="Field change preview" class="space-y-3">
								<h3 class="text-lg font-semibold">Field change preview</h3>
								<p>
									Comparing with: <strong
										>{data.preview.organisation_name ?? 'Proposed new organisation'}</strong
									>
								</p>
								<p class="text-sm">
									This comparison does not select a match or approve changes. Existing values and
									manual corrections are protected. Flags are reviewed individually and the address
									is reviewed as a complete group. ABNs remain unverified.
								</p>
								<a class="anchor" href={previewHref('')}>Preview as a new organisation</a>
								<FieldGroups fields={data.preview.fields} />
							</section>
						{/if}
						{#if data.preview && queue.detail.review && ['link', 'create'].includes(queue.detail.review.decision) && data.preview.organisation_id === queue.detail.review.organisation_id}
							<form method="POST" use:enhance class="card preset-tonal space-y-3 p-4">
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
								/>
								<p>
									Only selected values will be applied. A new organisation requires its name and
									will be public. Existing visibility is preserved.
								</p>
								{#key JSON.stringify(data.preview)}
									<FieldGroups fields={data.preview.fields} selectable />
								{/key}
								{#if form && 'intent' in form && form.intent === 'approve'}
									<p role="status" class="text-sm font-medium">{form.message}</p>
									{#if 'sourceBlocked' in form && form.sourceBlocked && data.isSiteAdmin}
										<a
											class="anchor"
											href={`${resolve('/admin/sources')}?${new URLSearchParams({ run: queue.run!, version: queue.detail.id })}`}
											>Review and enable source</a
										>
									{/if}
								{/if}
								<button class="btn preset-filled-primary-500">Save field approval</button>
							</form>
						{/if}
						{#if data.withdrawal}<WithdrawalControls
								run={queue.run!}
								version={queue.detail.id}
								status={data.withdrawal}
								fields={data.withdrawalFields}
							/>{/if}
						{#if data.approvals.length}
							<section aria-label="Saved field approvals" class="space-y-3">
								<h3 class="text-lg font-semibold">Saved field approvals</h3>
								{#each data.approvals as approval}<article
										class="card border-surface-200-800 space-y-2 border p-4"
									>
										<p>
											Approved {approval.approved_at} · review revision {approval.review_revision}
										</p>
										<p>Target: {approval.organisation_id ?? 'New public organisation'}</p>
										<ul>
											{#each approval.fields as field}<li class="break-all">
													{field.field}: {display(field.current_value)} → {display(
														field.source_value
													)} (revision {field.revision})
												</li>{/each}
										</ul>
										{#if approval.published_at}<p>Published {approval.published_at}</p>
											<a
												class="anchor"
												href={resolve('/organisations/[id]', {
													id: approval.published_organisation!
												})}>View organisation</a
											>
										{:else}<form method="POST" use:enhance>
												<input type="hidden" name="intent" value="publish" /><input
													type="hidden"
													name="approval"
													value={approval.id}
												/><button class="btn preset-filled-primary-500"
													>Publish these approved fields</button
												>
											</form>{/if}
									</article>{/each}
							</section>
						{/if}
						{#if queue.detail.review}<p class="text-sm">
								Saved decision: {queue.detail.review.decision} · revision {queue.detail.review
									.revision} · {queue.detail.review.reviewed_at}
							</p>{/if}
						<form method="POST" use:enhance class="space-y-4">
							<input type="hidden" name="run" value={queue.run!} /><input
								type="hidden"
								name="version"
								value={queue.detail.id}
							/><input type="hidden" name="revision" value={queue.detail.review?.revision ?? 0} />
							<label class="label"
								>Decision<select
									class="select"
									name="decision"
									required
									value={queue.detail.review?.decision ?? ''}
									><option value="" disabled>Select a decision</option><option value="link"
										>Propose link to existing organisation</option
									><option value="create">Propose new organisation</option><option value="defer"
										>Defer for investigation</option
									><option value="reject">Reject this version</option></select
								></label
							>
							<label class="label"
								>Organisation (link decisions only)<select
									class="select"
									name="organisation"
									value={queue.detail.review?.organisation_id ?? ''}
									><option value="">No organisation selected</option
									>{#if queue.detail.review?.organisation_id && !queue.candidates.some((c) => c.org_id === queue.detail!.review?.organisation_id)}<option
											value={queue.detail.review.organisation_id}
											>Previously selected: {queue.detail.review.organisation_id}</option
										>{/if}{#each queue.candidates as candidate}<option value={candidate.org_id}
											>{candidate.entity_name} · {candidate.abn ?? candidate.org_id}</option
										>{/each}</select
								></label
							>
							<label class="label"
								>Reason and identity checks<textarea
									class="textarea"
									name="note"
									rows="4"
									required
									maxlength="2000"
									value={queue.detail.review?.note ?? ''}
								></textarea></label
							>
							<button class="btn preset-filled-primary-500">Save review</button>
						</form>
					{/key}
				{:else}<p>Select a staged record to review.</p>{/if}
			</section>
		</div>
	{/if}
</div>
