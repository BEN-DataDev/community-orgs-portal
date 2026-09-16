<script lang="ts">
	import { enhance } from '$app/forms';
	import type { z } from 'zod';
	import type { withdrawalSchema, fieldPreviewSchema } from '$lib/server/ingestion-review';
	let {
		run,
		version,
		status,
		fields
	}: {
		run: string;
		version: string;
		status: z.infer<typeof withdrawalSchema>;
		fields: z.infer<typeof fieldPreviewSchema>['fields'];
	} = $props();
	let scope = $state('*');
	const expected = $derived({
		organisation_id: status.organisation_id,
		...(scope !== '*' && status.organisation_id
			? { field: fields.find((f) => f.field === scope) }
			: {})
	});
</script>

<section
	aria-label="Withdrawal and suppression"
	class="card border-surface-200-800 space-y-3 border p-4"
>
	<h3 class="text-lg font-semibold">Withdrawal and suppression</h3>
	<p>Target: {status.organisation_id ?? 'Unpublished source record'}</p>
	{#each status.suppressions as item}<p class="text-sm">
			<strong>{item.field === '*' ? 'Entire record' : item.field} suppressed</strong> · {item.suppressed_at}
			· {item.reason}
		</p>{/each}
	<form method="POST" use:enhance class="space-y-3">
		<input type="hidden" name="intent" value="suppress" /><input
			type="hidden"
			name="run"
			value={run}
		/><input type="hidden" name="version" value={version} /><input
			type="hidden"
			name="expected"
			value={JSON.stringify(expected)}
		/>
		<label class="label"
			>Scope<select class="select" name="field" bind:value={scope}
				><option value="*">Entire record — withdraw organisation from public view</option><option
					value="abn">ABN — remove value and block restoration</option
				><option value="website">Website — remove value and block restoration</option></select
			></label
		>
		<p class="text-sm">
			Entire-record withdrawal makes the linked organisation private, including when it already
			existed before import. Field removal clears the current value, including human corrections.
			This also blocks later imports. There is no restore action here.
		</p>
		{#if scope !== '*' && status.organisation_id}<p class="text-sm break-all">
				Current value: {String(fields.find((f) => f.field === scope)?.current_value ?? 'None')}
			</p>{/if}
		<label class="label"
			>Reason (private)<textarea class="textarea" name="reason" required maxlength="2000" rows="3"
			></textarea></label
		>
		<label class="flex items-start gap-2"
			><input class="checkbox" type="checkbox" name="confirmed" value="yes" required />I confirm
			removal of the selected content and blocking its restoration.</label
		>
		<button class="btn preset-filled-error-500">Apply suppression</button>
	</form>
</section>
