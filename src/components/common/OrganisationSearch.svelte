<script lang="ts">
	import { debounce } from '$lib/utils/debounce';

	import type { Database } from '$lib/db.types';
	import type { SupabaseClient } from '@supabase/supabase-js';

	type Organisation = Database['community_orgs']['Tables']['organisations']['Row'];

	interface Props {
		selected: Organisation | null;
		placeholder?: string;
		excludeIds?: number[];
		id?: string;
		supabase: SupabaseClient;
	}

	let {
		selected = $bindable(null),
		placeholder = 'Search organisations...',
		excludeIds = [],
		id = '',
		supabase
	}: Props = $props();

	let searchTerm = $state('');
	let results = $state<Organisation[]>([]);
	let isLoading = $state(false);
	let showResults = $state(false);

	const searchOrganisations = debounce(async (term: string) => {
		if (term.length < 2) {
			results = [];
			return;
		}

		isLoading = true;

		const { data, error } = await supabase
			.from('organisations')
			.select('*')
			.ilike('legal_name', `%${term}%`)
			.not('org_id', 'in', `(${excludeIds.join(',')})`)
			.limit(10);

		isLoading = false;

		if (!error && data) {
			results = data as Organisation[];
		}
	}, 300);

	function handleSelect(org: Organisation) {
		selected = org;
		searchTerm = org.legal_name;
		showResults = false;
	}

	function handleFocus() {
		if (searchTerm.length >= 2) {
			showResults = true;
		}
	}

	function handleBlur() {
		setTimeout(() => {
			showResults = false;
		}, 200);
	}
</script>

<div class="relative">
	<input
		type="text"
		{id}
		bind:value={searchTerm}
		oninput={() => {
			searchOrganisations(searchTerm);
			showResults = true;
		}}
		onfocus={handleFocus}
		onblur={handleBlur}
		{placeholder}
		class="w-full rounded-md border px-4 py-2"
	/>

	{#if isLoading}
		<div class="absolute right-3 top-2.5">
			<div
				class="h-5 w-5 animate-spin rounded-full border-2 border-indigo-500 border-t-transparent"
			></div>
		</div>
	{/if}

	{#if showResults && results.length > 0}
		<div
			class="absolute z-50 mt-1 max-h-60 w-full overflow-auto rounded-md border bg-white shadow-lg"
		>
			{#each results as org}
				<button
					type="button"
					class="w-full px-4 py-2 text-left hover:bg-gray-100 focus:bg-gray-100 focus:outline-none"
					onclick={() => handleSelect(org)}
				>
					<div>{org.legal_name}</div>
					{#if org.trading_name}
						<div class="text-sm text-gray-600">Trading as: {org.trading_name}</div>
					{/if}
				</button>
			{/each}
		</div>
	{/if}
</div>
