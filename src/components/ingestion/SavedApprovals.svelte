<script lang="ts">
	import { enhance } from '$app/forms';
	import { resolve } from '$app/paths';
	import type { z } from 'zod';
	import type { approvalsSchema } from '$lib/server/ingestion-review';
	let {
		approvals,
		savedApprovalId = null,
		message = null
	}: {
		approvals: z.infer<typeof approvalsSchema>;
		savedApprovalId?: string | null;
		message?: string | null;
	} = $props();
	let dialog: HTMLDialogElement;
	let lastOpened: string | null = null;
	$effect(() => {
		if (
			savedApprovalId &&
			savedApprovalId !== lastOpened &&
			approvals.some((a) => a.id === savedApprovalId)
		) {
			dialog.showModal();
			lastOpened = savedApprovalId;
		}
	});
	function display(value: unknown) {
		return value == null ? '—' : typeof value === 'string' ? value : JSON.stringify(value);
	}
</script>

<button type="button" class="btn preset-tonal" onclick={() => dialog.showModal()}>
	View saved field approvals ({approvals.length})
</button>
<dialog
	bind:this={dialog}
	aria-labelledby="saved-approvals-title"
	aria-describedby="saved-approvals-description"
	class="dialog preset-filled-surface-100-900 max-h-[85dvh] w-[calc(100%-2rem)] max-w-3xl space-y-4 overflow-y-auto p-6"
>
	<header class="flex items-center justify-between gap-4">
		<h2 id="saved-approvals-title" class="text-xl font-bold">Saved field approvals</h2>
		<button type="button" class="btn preset-tonal" onclick={() => dialog.close()}>Close</button>
	</header>
	<p id="saved-approvals-description">
		Review the saved values before publishing. Saving approval does not publish any changes.
	</p>
	{#if message}<p role="status">{message}</p>{/if}
	{#each approvals as approval (approval.id)}<article
			class="card border-surface-200-800 space-y-2 border p-4"
		>
			<p>
				Approved {approval.approved_at} · review revision {approval.review_revision}
			</p>
			<p>Target: {approval.organisation_id ?? 'New public organisation'}</p>
			<ul>
				{#each approval.fields as field (field.field)}<li class="break-all">
						{field.field}: {display(field.current_value)} → {display(field.source_value)} (revision {field.revision})
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
					/><button class="btn preset-filled-primary-500">Publish these approved fields</button>
				</form>{/if}
		</article>{/each}
</dialog>
