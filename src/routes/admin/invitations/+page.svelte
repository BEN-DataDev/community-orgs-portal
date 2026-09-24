<script lang="ts">
	import { enhance } from '$app/forms';
	import { resolve } from '$app/paths';
	import type { PageProps } from './$types';
	let { data, form }: PageProps = $props();
	const labels: Record<string, string> = {
		pending: 'Pending',
		accepted: 'Accepted',
		cancelled: 'Cancelled',
		expired: 'Expired'
	};
	function pageHref(offset: number) {
		const params = new URLSearchParams({
			search: data.filters.search,
			status: data.filters.status,
			offset: String(offset)
		});
		return `${resolve('/admin/invitations')}?${params}`;
	}
</script>

<svelte:head><title>Invitation administration</title></svelte:head>
<div class="space-y-6">
	<header class="space-y-2">
		<a class="anchor" href={resolve('/admin')}>Back to Admin</a><a
			class="anchor"
			href={resolve('/admin/stewardship')}>Stewardship administration</a
		>
		<h1 class="text-2xl font-bold">Invitation administration</h1>
		<p>Review every email-bound owner invitation and close pending handoffs.</p>
		<p class="text-sm">
			Responsible role: <strong>Portal Administrator</strong>. Issue a new invitation from an
			unclaimed organisation’s access screen.
		</p>
	</header>
	{#if form?.message}<p role="status" class="card preset-tonal p-4">{form.message}</p>{/if}
	<form method="GET" class="card preset-tonal grid gap-3 p-4 sm:grid-cols-2">
		<label class="label"
			>Organisation or recipient<input
				class="input"
				name="search"
				value={data.filters.search}
				maxlength="100"
				placeholder="Name, email or UUID"
			/></label
		><label class="label"
			>Status<select class="select" name="status" value={data.filters.status}
				><option value="">All statuses</option
				>{#each Object.entries(labels) as [status, label]}<option value={status}>{label}</option
					>{/each}</select
			></label
		><button class="btn preset-filled-primary-500 sm:col-span-2">Filter invitations</button>
	</form>
	<p>{data.queue.invitationTotal} matching invitations.</p>
	{#each data.queue.invitations as invitation (invitation.id)}<article
			class="card border-surface-200-800 space-y-3 border p-4"
		>
			<header class="flex flex-wrap justify-between gap-2">
				<div>
					<h2 class="font-semibold">{invitation.organisationName}</h2>
					<p>
						{invitation.email} · <span class="badge preset-tonal">{labels[invitation.status]}</span>
					</p>
				</div>
				<a
					class="anchor"
					href={resolve('/organisations/[id]/access', { id: invitation.organisationId })}
					>Manage organisation access</a
				>
			</header>
			<p class="text-sm">
				Outcome: {invitation.targetStewardship === 'self_managed' ? 'Self-managed' : 'Co-managed'} · issued
				{new Date(invitation.invitedAt).toLocaleString()} · expires {new Date(
					invitation.expiresAt
				).toLocaleString()}
			</p>
			<p class="font-mono text-sm break-all">{invitation.id}</p>
			{#if invitation.status === 'pending'}<a
					class="anchor break-all"
					href={resolve('/invitations/[id]', { id: invitation.id })}>Acceptance link</a
				>{/if}{#if invitation.canCancel}<form
					method="POST"
					action="?/cancel"
					use:enhance
					class="flex flex-wrap items-end gap-3"
				>
					<input type="hidden" name="invitationId" value={invitation.id} /><label
						class="label flex-1"
						>Cancellation reason<input
							class="input"
							name="reason"
							required
							maxlength="2000"
						/></label
					><button class="btn preset-tonal-error">Cancel invitation</button>
				</form>{/if}
		</article>{:else}<p>No invitations match this filter.</p>{/each}
	<nav aria-label="Invitation pages" class="flex gap-4">
		{#if data.filters.offset > 0}<a
				class="anchor"
				href={pageHref(Math.max(0, data.filters.offset - 50))}>Previous</a
			>{/if}{#if data.filters.offset + 50 < data.queue.invitationTotal}<a
				class="anchor"
				href={pageHref(data.filters.offset + 50)}>Next</a
			>{/if}
	</nav>
</div>
