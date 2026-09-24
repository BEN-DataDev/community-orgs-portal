<script lang="ts">
	import { enhance } from '$app/forms';
	import type { PageData, ActionData } from './$types';
	let { data, form }: { data: PageData; form: ActionData } = $props();
</script>

<svelte:head><title>Manage access · {data.roster.name}</title></svelte:head>
<div class="space-y-6">
	<h1 class="h1">Manage access</h1>
	<p>{data.roster.name}</p>
	<p>
		Grant existing roles to registered accounts. Assignments apply only to this organisation. Grants
		have no expiry; granting an existing role reactivates it and removes its expiry.
	</p>
	<p>
		You cannot revoke your own assignments. Before removing an owner, grant another account a
		non-expiring owner role.
	</p>
	{#if form?.message}<p role="status" class="card preset-tonal p-4">{form.message}</p>{/if}
	{#if form?.invitationUrl}
		<p class="card preset-tonal-success p-4">
			Acceptance link: <a class="anchor break-all" href={form.invitationUrl}>{form.invitationUrl}</a
			>
		</p>
	{/if}
	{#if data.roster.canInvite}
		<form
			method="POST"
			action="?/invite"
			use:enhance
			class="card bg-surface-100-900 max-w-xl space-y-4 p-4"
		>
			<h2 class="h2">Invite an owner</h2>
			<p class="text-sm">
				Acceptance is restricted to a registered account with this verified email address. The link
				can be delivered separately from the portal.
			</p>
			<label class="label"
				><span class="label-text">Email</span><input
					class="input"
					name="email"
					type="email"
					required
				/></label
			>
			<label class="label"
				><span class="label-text">Stewardship after acceptance</span><select
					class="select"
					name="targetStewardship"
					required
					><option value="self_managed">Self-managed</option><option value="co_managed"
						>Co-managed (approved continuing portal support)</option
					></select
				></label
			>
			<label class="label"
				><span class="label-text">Expires after</span><select
					class="select"
					name="expiresInDays"
					required
					><option value="7">7 days</option><option value="14">14 days</option><option value="30"
						>30 days</option
					></select
				></label
			>
			<label class="label"
				><span class="label-text">Decision reason</span><input
					class="input"
					name="reason"
					maxlength="2000"
					required
				/></label
			>
			<label class="label"
				><span class="label-text">Approval reference</span><input
					class="input"
					name="approvalReference"
					maxlength="500"
					required
				/></label
			>
			<label class="label"
				><span class="label-text">Invitation note</span><textarea
					class="textarea"
					name="note"
					maxlength="4000"
					rows="3"
					required
				></textarea></label
			>
			<button class="btn preset-filled-primary-500" type="submit">Issue invitation</button>
		</form>
	{/if}
	<form
		method="POST"
		action="?/grant"
		use:enhance
		class="card bg-surface-100-900 max-w-xl space-y-4 p-4"
	>
		<h2 class="h2">Grant a role</h2>
		<label class="label"
			><span>Registered account ID</span><input
				class="input"
				name="userId"
				required
				placeholder="Account UUID"
			/></label
		>
		<p class="text-sm">
			Ask the account holder for their ID from Account settings → My access. Your account ID is <span
				class="font-mono break-all">{data.actorId}</span
			>.
		</p>
		<label class="label"
			><span>Role</span><select class="select" name="roleId" required
				><option value="">Select a role</option>{#each data.roster.roles as role (role.id)}<option
						value={role.id}>{role.name}</option
					>{/each}</select
			></label
		>
		<button class="btn preset-filled-primary-500" type="submit">Grant role</button>
	</form>
	<section class="space-y-4" aria-label="Owner invitations">
		<h2 class="h2">Owner invitations ({data.roster.invitations.length})</h2>
		{#each data.roster.invitations as invitation (invitation.id)}
			<article class="card bg-surface-100-900 space-y-3 p-4">
				<h3 class="h3">{invitation.email} · {invitation.status}</h3>
				<p class="text-sm">
					Outcome: {invitation.targetStewardship === 'self_managed' ? 'Self-managed' : 'Co-managed'} ·
					expires {new Date(invitation.expiresAt).toLocaleString()}
				</p>
				{#if invitation.status === 'pending'}
					<a class="anchor break-all" href={`/invitations/${invitation.id}`}
						>/invitations/{invitation.id}</a
					>
				{/if}
				{#if invitation.canCancel}
					<form method="POST" action="?/cancelInvitation" use:enhance class="max-w-xl space-y-3">
						<input type="hidden" name="invitationId" value={invitation.id} />
						<label class="label"
							><span class="label-text">Cancellation reason</span><input
								class="input"
								name="reason"
								maxlength="2000"
								required
							/></label
						>
						<button class="btn preset-tonal-error" type="submit">Cancel invitation</button>
					</form>
				{/if}
			</article>
		{:else}<p>No owner invitations have been issued.</p>{/each}
	</section>
	<section class="space-y-4" aria-label="Role assignments">
		<h2 class="h2">Assignments ({data.roster.assignments.length})</h2>
		{#each data.roster.assignments as assignment (assignment.id)}
			<article class="card bg-surface-100-900 space-y-3 p-4">
				<h3 class="h3">{assignment.role} · {assignment.status}</h3>
				<p class="font-mono text-sm break-all">
					{assignment.userId}{assignment.userId === data.actorId ? ' (you)' : ''}
				</p>
				<p class="text-sm">Expiry: {assignment.expiresAt ?? 'None'}</p>
				{#if assignment.canRevoke}
					<form method="POST" action="?/revoke" use:enhance class="max-w-xl space-y-3">
						<input type="hidden" name="userId" value={assignment.userId} /><input
							type="hidden"
							name="roleId"
							value={assignment.roleId}
						/>
						<label class="label"
							><span>Reason (optional)</span><input
								class="input"
								name="reason"
								maxlength="1000"
							/></label
						>
						<label class="flex items-center gap-2"
							><input type="checkbox" name="confirm" value="yes" required /> Revoke this {assignment.role}
							assignment</label
						>
						<button class="btn preset-tonal-error" type="submit">Revoke role</button>
					</form>
				{/if}
			</article>
		{:else}<p>No role assignments. A platform administrator can grant the first owner.</p>{/each}
	</section>
</div>
