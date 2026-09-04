/src/routes/relationships/+page.server.ts

```ts
import { supabase } from '$lib/services/supabase';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ url }) => {
	const searchParams = url.searchParams;
	const page = parseInt(searchParams.get('page') || '1');
	const limit = 10;
	const offset = (page - 1) * limit;

	const {
		data: relationships,
		error,
		count
	} = await supabase
		.from('relationships')
		.select(
			`
            *,
            organisations!relationships_org_id_fkey (
                legal_name,
                trading_name
            )
        `,
			{ count: 'exact' }
		)
		.range(offset, offset + limit - 1);

	return {
		relationships,
		totalCount: count || 0,
		currentPage: page,
		totalPages: Math.ceil((count || 0) / limit)
	};
};
```

/src/routes/relationships/+page.svelte

```svelte
<script lang="ts">
	import { enhance } from '$app/forms';
	import RelationshipsTable from '$lib/components/tables/RelationshipsTable.svelte';
	import Pagination from '$lib/components/common/Pagination.svelte';
	import { Button } from '$lib/components/common';

	let { data } = $props();

	let { relationships, totalCount, currentPage, totalPages } = $derived(data);
</script>

<div class="container mx-auto px-4 py-8">
	<div class="mb-6 flex items-center justify-between">
		<h1 class="text-2xl font-bold">Organisation Relationships</h1>
		<Button href="/relationships/new">Add New Relationship</Button>
	</div>

	<RelationshipsTable {relationships} />

	<div class="mt-4">
		<Pagination {currentPage} {totalPages} baseUrl="/relationships" />
	</div>
</div>
```

RelationshipsTable.svelte

```svelte
<script lang="ts">
	import { formatDate } from '$lib/utils/formatters';

	interface Props {
		relationships: Array<{
			relationship_id: number;
			org_id: number;
			partner_org: string;
			relationship_type: string;
			start_date: string;
			end_date: string | null;
			organisations: {
				legal_name: string;
				trading_name: string | null;
			};
		}>;
	}

	let { relationships }: Props = $props();
</script>

<div class="overflow-x-auto">
	<table class="min-w-full divide-y divide-gray-200">
		<thead class="bg-gray-50">
			<tr>
				<th class="px-6 py-3 text-left text-xs font-medium tracking-wider text-gray-500 uppercase">
					Organisation
				</th>
				<th class="px-6 py-3 text-left text-xs font-medium tracking-wider text-gray-500 uppercase">
					Partner
				</th>
				<th class="px-6 py-3 text-left text-xs font-medium tracking-wider text-gray-500 uppercase">
					Type
				</th>
				<th class="px-6 py-3 text-left text-xs font-medium tracking-wider text-gray-500 uppercase">
					Duration
				</th>
				<th class="px-6 py-3 text-left text-xs font-medium tracking-wider text-gray-500 uppercase">
					Actions
				</th>
			</tr>
		</thead>
		<tbody class="divide-y divide-gray-200 bg-white">
			{#each relationships as relationship}
				<tr>
					<td class="px-6 py-4 whitespace-nowrap">
						{relationship.organisations.legal_name}
					</td>
					<td class="px-6 py-4 whitespace-nowrap">
						{relationship.partner_org}
					</td>
					<td class="px-6 py-4 whitespace-nowrap">
						{relationship.relationship_type}
					</td>
					<td class="px-6 py-4 whitespace-nowrap">
						{formatDate(relationship.start_date)} -
						{relationship.end_date ? formatDate(relationship.end_date) : 'Present'}
					</td>
					<td class="px-6 py-4 whitespace-nowrap">
						<a
							href="/relationships/{relationship.relationship_id}"
							class="text-indigo-600 hover:text-indigo-900"
						>
							View
						</a>
					</td>
				</tr>
			{/each}
		</tbody>
	</table>
</div>
```

/src/routes/relationships/[id]/+page.server.ts

```ts
import { supabase } from '$lib/services/supabase';
import type { PageServerLoad } from './$types';
import { error } from '@sveltejs/kit';

export const load: PageServerLoad = async ({ params }) => {
	const { data: relationship, error: relationshipError } = await supabase
		.from('relationships')
		.select(
			`
            *,
            organisations!relationships_org_id_fkey (
                legal_name,
                trading_name
            ),
            inserted_by (
                email,
                name
            ),
            last_edited_by (
                email,
                name
            )
        `
		)
		.eq('relationship_id', params.id)
		.single();

	if (relationshipError) {
		throw error(404, 'Relationship not found');
	}

	return {
		relationship
	};
};
```

/src/routes/relationships/[id]/+page.svelte

```svelte
<script lang="ts">
	import { formatDate } from '$lib/utils/formatters';
	import { Button, Card } from '$lib/components/common';
	import RelationshipForm from '$lib/components/forms/RelationshipForm.svelte';

	let { data } = $props();

	let { relationship } = $derived(data);
	let isEditing = $state(false);
</script>

<div class="container mx-auto px-4 py-8">
	<div class="mb-6 flex items-center justify-between">
		<h1 class="text-2xl font-bold">
			Relationship Details: {relationship.organisations.legal_name} - {relationship.partner_org}
		</h1>
		<Button on:click={() => (isEditing = !isEditing)}>
			{isEditing ? 'Cancel Edit' : 'Edit Relationship'}
		</Button>
	</div>

	{#if isEditing}
		<RelationshipForm {relationship} on:save={() => (isEditing = false)} />
	{:else}
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
			<Card title="Primary Organisation">
				<p class="text-lg">{relationship.organisations.legal_name}</p>
				{#if relationship.organisations.trading_name}
					<p class="text-sm text-gray-600">
						Trading as: {relationship.organisations.trading_name}
					</p>
				{/if}
			</Card>

			<Card title="Partner Organisation">
				<p class="text-lg">{relationship.partner_org}</p>
				<p class="text-sm text-gray-600">
					Type: {relationship.relationship_type}
				</p>
			</Card>

			<Card title="Duration">
				<p>Start Date: {formatDate(relationship.start_date)}</p>
				<p>End Date: {relationship.end_date ? formatDate(relationship.end_date) : 'Ongoing'}</p>
			</Card>

			<Card title="Metadata">
				<p>Created by: {relationship.inserted_by.name}</p>
				<p>Created at: {formatDate(relationship.inserted_at)}</p>
				<p>Last edited by: {relationship.last_edited_by.name}</p>
				<p>Last edited at: {formatDate(relationship.last_edited_at)}</p>
			</Card>
		</div>
	{/if}
</div>
```

RelationshipForm.svelte

```svelte
<script lang="ts">
	import { preventDefault } from 'svelte/legacy';

	import { createEventDispatcher } from 'svelte';
	import { supabase } from '$lib/services/supabase';
	import { Button } from '$lib/components/common';

	let {
		relationship = $bindable({
			org_id: null,
			partner_org: '',
			relationship_type: '',
			start_date: '',
			end_date: null
		})
	} = $props();

	const dispatch = createEventDispatcher();

	async function handleSubmit() {
		const { data, error } = await supabase.from('relationships').upsert({
			...relationship,
			last_edited_at: new Date().toISOString()
		});

		if (!error) {
			dispatch('save');
		}
	}
</script>

<form onsubmit={preventDefault(handleSubmit)} class="space-y-6">
	<div>
		<label class="block text-sm font-medium text-gray-700"> Partner Organisation </label>
		<input
			type="text"
			bind:value={relationship.partner_org}
			class="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
			required
		/>
	</div>

	<div>
		<label class="block text-sm font-medium text-gray-700"> Relationship Type </label>
		<select
			bind:value={relationship.relationship_type}
			class="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
			required
		>
			<option value="">Select type...</option>
			<option value="Partner">Partner</option>
			<option value="Supplier">Supplier</option>
			<option value="Funder">Funder</option>
			<option value="Network">Network</option>
		</select>
	</div>

	<div>
		<label class="block text-sm font-medium text-gray-700"> Start Date </label>
		<input
			type="date"
			bind:value={relationship.start_date}
			class="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
			required
		/>
	</div>

	<div>
		<label class="block text-sm font-medium text-gray-700"> End Date </label>
		<input
			type="date"
			bind:value={relationship.end_date}
			class="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
		/>
	</div>

	<div class="flex justify-end space-x-4">
		<Button type="submit">Save Changes</Button>
	</div>
</form>
```
