<script lang="ts">
	import type { z } from 'zod';
	import type { fieldPreviewSchema } from '$lib/server/ingestion-review';
	type Field = z.infer<typeof fieldPreviewSchema>['fields'][number];
	let { fields, selectable = false }: { fields: Field[]; selectable?: boolean } = $props();
	let selected = $state<string[]>([]);
	const sections = [
		'Overview',
		'Legal',
		'Contact',
		'Operations',
		'Finance',
		'Governance',
		'Unmapped'
	];
	function eligible(field: Field) {
		return ['new', 'changed'].includes(field.status) && !field.protected;
	}
	function display(value: unknown) {
		return value == null
			? 'Unknown / not supplied'
			: typeof value === 'string'
				? value
				: JSON.stringify(value, null, 2);
	}
	function selectGroup(group: Field[], checked: boolean) {
		const values = group.filter(eligible).map((field) => JSON.stringify(field));
		selected = checked
			? [...new Set([...selected, ...values])]
			: selected.filter((value) => !values.includes(value));
	}
</script>

{#each sections as section (section)}
	{@const group = fields.filter((field) => field.section === section)}
	{#if group.length}
		<fieldset class="fieldset space-y-3" aria-label={`${section} fields`}>
			<legend class="legend font-semibold">{section}</legend>
			<p class="text-sm">
				{group.filter(eligible).length} eligible ·
				{group.filter((f) => ['conflict', 'ambiguous'].includes(f.status)).length} conflicting ·
				{group.filter((f) => f.status === 'invalid').length} invalid ·
				{group.filter((f) => ['missing', 'unmapped', 'suppressed', 'unchanged'].includes(f.status))
					.length} excluded
			</p>
			{#if selectable}
				<label class="flex items-center gap-2">
					<input
						type="checkbox"
						class="checkbox"
						disabled={!group.some(eligible)}
						checked={group.some(eligible) &&
							group.filter(eligible).every((f) => selected.includes(JSON.stringify(f)))}
						onchange={(event) => selectGroup(group, event.currentTarget.checked)}
					/>
					Select all eligible in {section}
				</label>
			{/if}
			<div class="table-wrap">
				<table class="table text-sm">
					<thead><tr><th>Field</th><th>Current</th><th>Proposed</th><th>Assessment</th></tr></thead>
					<tbody>
						{#each group as field (field.field)}
							<tr>
								<th scope="row">
									{#if selectable && eligible(field)}
										<label class="flex items-start gap-2">
											<input
												class="checkbox"
												type="checkbox"
												name="field"
												value={JSON.stringify(field)}
												bind:group={selected}
											/>
											<span>{field.label}</span>
										</label>
									{:else}{field.label}{/if}
									{#if field.atomic_group}<span class="block text-xs"
											>Atomic address group; omitted components are retained.</span
										>{/if}
								</th>
								<td
									><pre class="max-w-80 break-words whitespace-pre-wrap">{display(
											field.current_value
										)}</pre></td
								>
								<td
									><pre class="max-w-80 break-words whitespace-pre-wrap">{display(
											field.source_value
										)}</pre></td
								>
								<td class="min-w-40 whitespace-normal">
									<strong>{field.status}</strong>
									{#if field.protected}<p>Protected · revision {field.revision}</p>{/if}
									{#if field.status === 'missing'}<p>Keep the current value.</p>{/if}
									{#if field.status === 'unmapped'}<p>
											Supplied evidence needs a qualified mapping.
										</p>{/if}
									{#if field.status === 'invalid'}<p>
											Value fails the destination’s validation.
										</p>{/if}
									{#if field.status === 'suppressed'}<p>
											Publication and restoration blocked.
										</p>{/if}
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		</fieldset>
	{/if}
{/each}
