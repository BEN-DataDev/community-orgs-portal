<script lang="ts">
	import { debounce } from '$lib/utils/debounce';

	import type { Database } from '$lib/db.types';
	import type { TypedSupabaseClient } from '$lib/supabase-client';

	type Organisation = Database['community_orgs']['Tables']['organisations']['Row'];

	interface Props {
		selected: Organisation | null;
		placeholder?: string;
		excludeIds?: Organisation['org_id'][];
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

	let searchError = $state('');
	let hasSearched = $state(false);
	let searchVersion = 0;

	const searchOrganisations = debounce(async (term: string, version: number) => {
		if (version !== searchVersion || term.length < 2) return;

		try {
			let request = supabase
				.from('organisations')
				.select('*')
				.ilike('entity_name', `%${escapeFilterValue(term)}%`)
				.limit(10);

			// Avoid an empty PostgREST in-list and preserve UUIDs as strings.
			if (excludeIds.length > 0) {
				request = request.not('org_id', 'in', `(${excludeIds.join(',')})`);
			}

			const { data, error } = await request;
			if (version !== searchVersion) return;
			if (error) throw error;
			results = data ?? [];
			hasSearched = true;
		} catch {
			if (version !== searchVersion) return;
			results = [];
			searchError = 'Could not search organisations. Please try again.';
		} finally {
			if (version === searchVersion) isLoading = false;
		}
	}, 300);

	function handleInput(value: string) {
		searchTerm = value;
		selected = null;
		results = [];
		searchError = '';
		hasSearched = false;
		showResults = true;
		isLoading = value.length >= 2;
		searchOrganisations(value, ++searchVersion);
	}

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
		searchVersion++;
		isLoading = false;
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
		value={searchTerm}
		oninput={(event) => handleInput(event.currentTarget.value)}
		onfocus={handleFocus}
		onblur={handleBlur}
		{placeholder}
		class="input"
	/>

	{#if searchError}
		<p role="alert" class="text-error-500 text-sm">{searchError}</p>
	{:else if showResults && hasSearched && results.length === 0}
		<p role="status" class="text-surface-600-400 text-sm">No organisations found.</p>
	{/if}

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
			{#each results as org (org.org_id)}
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
