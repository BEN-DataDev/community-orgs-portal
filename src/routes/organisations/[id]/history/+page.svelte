<script lang="ts">
	import { formatDate } from '$lib/utils/formatters';

	let { data } = $props();
	let { historicalInfo, organisation } = $derived(data);
	let isEditing = $state(false);
</script>

<div class="container mx-auto px-4 py-8">
	<div class="mb-6 flex items-center justify-between">
		<div>
			<h1 class="text-2xl font-bold">Historical Information</h1>
			<p class="text-gray-600">{organisation.legal_name}</p>
		</div>
		<button class="variant-filled btn" onclick={() => (isEditing = !isEditing)}>
			{isEditing ? 'Cancel' : 'Add Historical Entry'}
		</button>
	</div>

	{#if isEditing}
		<card>
			<form method="POST" action="?/updateHistory" class="space-y-6">
				<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
					<div>
						<label for="foundingMembers">Founding Members</label>
						<input
							type="text"
							id="foundingMembers"
							name="foundingMembers"
							placeholder="Comma-separated names"
						/>
					</div>

					<div>
						<label for="milestoneDate">Milestone Date</label>
						<input type="date" id="milestoneDate" name="milestoneDate" required />
					</div>

					<div class="md:col-span-2">
						<label for="milestoneDescription">Milestone Description</label>
						<textarea id="milestoneDescription" name="milestoneDescription" rows="3" required
						></textarea>
					</div>

					<div class="md:col-span-2">
						<label for="structuralChanges">Structural Changes</label>
						<textarea
							id="structuralChanges"
							name="structuralChanges"
							rows="3"
							placeholder="Enter JSON format structural changes"
						></textarea>
					</div>
				</div>

				<div class="flex justify-end">
					<button type="submit">Save Historical Entry</button>
				</div>
			</form>
		</card>
	{/if}
	<div class="mt-6 space-y-6">
		{#each historicalInfo as entry}
			<card>
				<div class="space-y-4">
					<div class="flex items-start justify-between">
						<div>
							<h3 class="font-medium">{formatDate(entry.milestone_date ?? '')}</h3>
							<p class="text-gray-600">{entry.milestone_description}</p>
						</div>
					</div>

					{#if entry.founding_members?.length}
						<div>
							<h4 class="mb-2 font-medium">Founding Members</h4>
							<div class="flex flex-wrap gap-2">
								{#each entry.founding_members as member}
									<span class="rounded-full bg-gray-100 px-3 py-1 text-sm">
										{member}
									</span>
								{/each}
							</div>
						</div>
					{/if}

					{#if entry.structural_changes}
						<div>
							<h4 class="mb-2 font-medium">Structural Changes</h4>
							<pre class="rounded bg-gray-50 p-3 text-sm">
                                {JSON.stringify(entry.structural_changes, null, 2)}
                            </pre>
						</div>
					{/if}

					<div class="text-sm text-gray-500">
						Last edited by {entry.last_edited_by} on {formatDate(entry.last_edited_at ?? '')}
					</div>
				</div>
			</card>
		{/each}
	</div>
</div>
