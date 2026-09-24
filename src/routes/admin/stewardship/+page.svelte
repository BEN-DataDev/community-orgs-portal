<script lang="ts">
	import { enhance } from '$app/forms';
	import { resolve } from '$app/paths';
	import type { PageProps } from './$types';
	let { data, form }: PageProps = $props();
	const labels: Record<string, string> = {
		unclaimed: 'Unclaimed',
		invitation_pending: 'Invitation pending',
		self_managed: 'Self-managed',
		portal_managed: 'Portal-managed',
		co_managed: 'Co-managed',
		suspended: 'Suspended'
	};
	const transitions: Record<string, string[]> = {
		unclaimed: ['portal_managed', 'suspended'],
		invitation_pending: [],
		self_managed: ['co_managed', 'suspended'],
		portal_managed: ['unclaimed', 'suspended'],
		co_managed: ['self_managed', 'portal_managed', 'suspended'],
		suspended: ['unclaimed', 'portal_managed']
	};
	function pageHref(offset: number) {
		const params = new URLSearchParams({
			search: data.filters.search,
			state: data.filters.state,
			offset: String(offset)
		});
		return `${resolve('/admin/stewardship')}?${params}`;
	}
</script>

<svelte:head><title>Stewardship administration</title></svelte:head>
<div class="space-y-6">
	<header class="space-y-2">
		<a class="anchor" href={resolve('/admin')}>Back to Admin</a><a
			class="anchor"
			href={resolve('/admin/invitations')}>Invitation administration</a
		>
		<h1 class="text-2xl font-bold">Stewardship administration</h1>
		<p>Review current organisation governance and record an evidence-backed state decision.</p>
		<p class="text-sm">
			Responsible role: <strong>Portal Administrator</strong>. Invitation acceptance remains the
			only owner handoff path.
		</p>
	</header>
	{#if form?.message}<p role="status" class="card preset-tonal p-4">{form.message}</p>{/if}
	<div class="grid gap-2 sm:grid-cols-3 xl:grid-cols-6">
		{#each Object.entries(labels) as [state, label]}<div class="card preset-tonal p-3">
				<strong>{data.queue.stewardshipCounts[state] ?? 0}</strong><span class="block text-sm"
					>{label}</span
				>
			</div>{/each}
	</div>
	<form method="GET" class="card preset-tonal grid gap-3 p-4 sm:grid-cols-2">
		<label class="label"
			>Organisation<input
				class="input"
				name="search"
				value={data.filters.search}
				maxlength="100"
				placeholder="Name or UUID"
			/></label
		><label class="label"
			>State<select class="select" name="state" value={data.filters.state}
				><option value="">All states</option>{#each Object.entries(labels) as [state, label]}<option
						value={state}>{label}</option
					>{/each}</select
			></label
		><button class="btn preset-filled-primary-500 sm:col-span-2">Filter stewardship</button>
	</form>
	<p>{data.queue.stewardshipTotal} matching organisations.</p>
	{#each data.queue.organisations as organisation (organisation.organisationId)}<article
			class="card border-surface-200-800 space-y-3 border p-4"
		>
			<header class="flex flex-wrap justify-between gap-2">
				<div>
					<h2 class="font-semibold">{organisation.name}</h2>
					<p class="text-sm">
						{labels[organisation.state]} · revision {organisation.revision} · {organisation.updatedAt}
					</p>
				</div>
				<a class="anchor" href={resolve('/organisations/[id]', { id: organisation.organisationId })}
					>View organisation</a
				>
			</header>
			<details>
				<summary class="cursor-pointer font-medium">Current decision evidence</summary>
				<p>{organisation.reason}</p>
				<p>{organisation.note}</p>
				<p class="text-sm">
					Approval: {organisation.approvalReference ?? 'Not required'} · related: {organisation.relatedReference ??
						'None'}
				</p>
			</details>
			{#if transitions[organisation.state].length}<form
					method="POST"
					use:enhance
					class="grid gap-3 lg:grid-cols-2"
				>
					<input type="hidden" name="organisationId" value={organisation.organisationId} /><input
						type="hidden"
						name="revision"
						value={organisation.revision}
					/><label class="label"
						>Next state<select class="select" name="nextState" required
							><option value="">Select state</option
							>{#each transitions[organisation.state] as state}<option value={state}
									>{labels[state]}</option
								>{/each}</select
						></label
					><label class="label"
						>Approval reference<input
							class="input"
							name="approvalReference"
							maxlength="500"
						/></label
					><label class="label lg:col-span-2"
						>Decision reason<input class="input" name="reason" required maxlength="2000" /></label
					><label class="label lg:col-span-2"
						>Governance note<textarea
							class="textarea"
							name="note"
							required
							maxlength="4000"
							rows="2"
						></textarea></label
					><button class="btn preset-filled-primary-500 lg:col-span-2"
						>Record stewardship decision</button
					>
				</form>{:else}<p class="card preset-tonal-warning p-3">
					Close the pending invitation before recording another stewardship decision.
				</p>{/if}
			{#if organisation.state === 'unclaimed' || organisation.state === 'invitation_pending'}<a
					class="anchor"
					href={resolve('/organisations/[id]/access', { id: organisation.organisationId })}
					>Manage owner handoff →</a
				>{/if}
		</article>{:else}<p>No organisations match this filter.</p>{/each}
	<nav aria-label="Stewardship pages" class="flex gap-4">
		{#if data.filters.offset > 0}<a
				class="anchor"
				href={pageHref(Math.max(0, data.filters.offset - 50))}>Previous</a
			>{/if}{#if data.filters.offset + 50 < data.queue.stewardshipTotal}<a
				class="anchor"
				href={pageHref(data.filters.offset + 50)}>Next</a
			>{/if}
	</nav>
</div>
