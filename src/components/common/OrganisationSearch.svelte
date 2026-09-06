<script lang="ts">
	import { debounce } from '$lib/utils/debounce';

	import type { Database } from '$lib/db.types';
	import type { TypedSupabaseClient } from '$lib/supabase-client';

	type Organisation = Database['community_orgs']['Tables']['organisations']['Row'];

	interface Props {
		selected: Organisation | null;
		placeholder?: string;
		excludeIds?: number[];
		id?: string;
		supabase: TypedSupabaseClient;
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

		let request = supabase
			.from('organisations')
			.select('*')
			.ilike('entity_name', `%${escapeFilterValue(term)}%`)
			.limit(10);

		// `in.()` is a PostgREST syntax error, so only add the clause when it has members.
		if (excludeIds.length > 0) {
			request = request.not('org_id', 'in', `(${excludeIds.join(',')})`);
		}

		const { data, error } = await request;

		isLoading = false;

		if (!error && data) {
			results = data as Organisation[];
		}
	}, 300);

	/**
	 * PostgREST parses filter values out of the query string, where commas,
	 * parentheses and quotes are structural. Left raw, a search term containing
	 * them reshapes the filter instead of being matched. `%` and `_` are LIKE
	 * wildcards and are escaped so a search for them is literal.
	 */
	function escapeFilterValue(value: string): string {
		return value.replace(/[%_\\]/g, '\\$&').replace(/[(),."']/g, ' ');
	}

	function handleSelect(org: Organisation) {
		selected = org;
		searchTerm = org.entity_name;
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
		class="input"
	/>

	{#if isLoading}
		<div class="absolute top-2.5 right-3">
			<div
				class="border-primary-500 h-5 w-5 animate-spin rounded-full border-2 border-t-transparent"
			></div>
		</div>
	{/if}

	{#if showResults && results.length > 0}
		<div
			class="rounded-base border-surface-200-800 bg-surface-50-950 absolute z-50 mt-1 max-h-60 w-full overflow-auto border shadow-lg"
		>
			{#each results as org}
				<button
					type="button"
					class="hover:preset-tonal focus:preset-tonal w-full px-4 py-2 text-left focus:outline-none"
					onclick={() => handleSelect(org)}
				>
					<div>{org.entity_name}</div>
					{#if org.description}
						<div class="text-surface-600-400 text-sm">{org.description}</div>
					{/if}
				</button>
			{/each}
		</div>
	{/if}
</div>
