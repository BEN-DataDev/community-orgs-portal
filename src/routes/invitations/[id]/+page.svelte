<script lang="ts">
	import { enhance } from '$app/forms';
	import type { ActionData, PageData } from './$types';
	let { data, form }: { data: PageData; form: ActionData } = $props();
</script>

<svelte:head
	><title>Organisation invitation · {data.invitation.organisationName}</title></svelte:head
>

<div class="mx-auto max-w-2xl space-y-6">
	<h1 class="h1">Organisation owner invitation</h1>
	<section class="card bg-surface-100-900 space-y-4 p-5">
		<h2 class="h2">{data.invitation.organisationName}</h2>
		<p>{data.invitation.note}</p>
		<dl class="grid gap-3 sm:grid-cols-2">
			<div>
				<dt class="font-medium">Invited email</dt>
				<dd>{data.invitation.email}</dd>
			</div>
			<div>
				<dt class="font-medium">Status</dt>
				<dd>{data.invitation.status}</dd>
			</div>
			<div>
				<dt class="font-medium">Expires</dt>
				<dd>{new Date(data.invitation.expiresAt).toLocaleString()}</dd>
			</div>
			<div>
				<dt class="font-medium">Stewardship</dt>
				<dd>
					{data.invitation.targetStewardship === 'self_managed' ? 'Self-managed' : 'Co-managed'}
				</dd>
			</div>
		</dl>
		{#if form?.message}<p role="status" class="preset-tonal p-4">{form.message}</p>{/if}
		{#if data.invitation.status === 'pending' && !form?.success}
			<form method="POST" action="?/accept" use:enhance>
				<button class="btn preset-filled-primary-500" type="submit">Accept ownership</button>
			</form>
		{/if}
		{#if form?.success}
			<a class="anchor" href={`/organisations/${data.invitation.organisationId}`}
				>Open organisation</a
			>
		{/if}
	</section>
</div>
