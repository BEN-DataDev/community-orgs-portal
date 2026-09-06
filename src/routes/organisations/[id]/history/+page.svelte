<script lang="ts">
	import { formatDate } from '$lib/utils/formatters';

	let { data, form } = $props();
	let { historicalInfo, organisation } = $derived(data);
	let isAdding = $state(false);
</script>

<div>
	<div class="mb-6 flex flex-wrap items-start justify-between gap-3">
		<div>
			<h1 class="text-2xl font-bold">Historical Information</h1>
			<p class="text-surface-600-400">{organisation.entity_name}</p>
		</div>
		<button class="btn preset-filled" onclick={() => (isAdding = !isAdding)}>
			{isAdding ? 'Cancel' : 'Add Historical Entry'}
		</button>
	</div>

	{#if form?.message}
		<p class="text-error-500 mb-4">{form.message}</p>
	{/if}

	{#if isAdding}
		<div class="card preset-outlined-surface-200-800 p-4">
			<form method="POST" action="?/addHistoryEntry" class="space-y-6">
				<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
					<div>
						<label class="label label-text" for="founding_members">Founding Members</label>
						<input
							class="input"
							type="text"
							id="founding_members"
							name="founding_members"
							placeholder="Comma-separated names"
						/>
					</div>

					<div>
						<label class="label label-text" for="milestone_date">Milestone Date</label>
						<input class="input" type="date" id="milestone_date" name="milestone_date" required />
						{#if form?.errors?.milestone_date}
							<p class="text-error-500 text-sm">{form.errors.milestone_date[0]}</p>
						{/if}
					</div>

					<div class="md:col-span-2">
						<label class="label label-text" for="milestone_description">Milestone Description</label
						>
						<textarea
							class="textarea"
							id="milestone_description"
							name="milestone_description"
							rows="3"
							required
						></textarea>
					</div>

					<div class="md:col-span-2">
						<label class="label label-text" for="structural_changes">Structural Changes</label>
						<textarea
							class="textarea"
							id="structural_changes"
							name="structural_changes"
							rows="3"
							placeholder="Optional. JSON, e.g. [&#123;&quot;year&quot;: 2019, &quot;change&quot;: &quot;Incorporated&quot;&#125;]"
						></textarea>
						{#if form?.errors?.structural_changes}
							<p class="text-error-500 text-sm">{form.errors.structural_changes[0]}</p>
						{/if}
					</div>
				</div>

				<div class="flex justify-end">
					<button class="btn preset-filled" type="submit">Save Historical Entry</button>
				</div>
			</form>
		</div>
	{/if}

	<div class="mt-6 space-y-6">
		{#each historicalInfo as entry (entry.history_id)}
			<div class="card preset-outlined-surface-200-800 space-y-4 p-4">
				<div>
					<h3 class="font-medium">
						{entry.milestone_date ? formatDate(entry.milestone_date) : 'Undated'}
					</h3>
					<p class="text-surface-600-400">{entry.milestone_description ?? '—'}</p>
				</div>

				{#if entry.founding_members?.length}
					<div>
						<h4 class="mb-2 font-medium">Founding Members</h4>
						<div class="flex flex-wrap gap-2">
							{#each entry.founding_members as member}
								<span class="bg-surface-100-900 rounded-full px-3 py-1 text-sm">{member}</span>
							{/each}
						</div>
					</div>
				{/if}

				{#if entry.structural_changes}
					<div>
						<h4 class="mb-2 font-medium">Structural Changes</h4>
						<pre
							class="bg-surface-50-950 overflow-x-auto rounded p-3 text-sm break-words whitespace-pre-wrap">{JSON.stringify(
								entry.structural_changes,
								null,
								2
							)}</pre>
					</div>
				{/if}

				<div class="text-surface-600-400 text-sm">
					Last edited {entry.last_edited_at ? formatDate(entry.last_edited_at) : '—'}
				</div>
			</div>
		{:else}
			<p class="text-surface-600-400">No history recorded yet.</p>
		{/each}
	</div>
</div>
