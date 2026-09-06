<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { Info } from 'lucide-svelte';

	/**
	 * Shown for the length of a guest session.
	 *
	 * A guest can read public organisations and nothing else — every write is
	 * refused by restrictive RLS — so the banner is the only thing explaining why
	 * the edit controls are absent.
	 *
	 * Signing up from here creates a *separate* permanent account rather than
	 * upgrading this one in place. That is deliberate and costs nothing: a guest
	 * owns no rows (writes are blocked), so there is no data to migrate and none
	 * of the identity-conflict handling in the Supabase anonymous guide applies.
	 */
	const redirectTo = $derived(page.url.pathname + page.url.search);
</script>

{#if page.data.isAnonymous}
	<aside
		class="preset-tonal-warning flex flex-wrap items-center justify-center gap-3 px-4 py-2 text-sm"
	>
		<Info class="h-4 w-4 shrink-0" />
		<span>You are browsing as a guest. Create an account to join or manage an organisation.</span>
		<a
			class="btn btn-sm preset-filled-primary-500"
			href={resolve('/auth/signup') + `?redirectTo=${encodeURIComponent(redirectTo)}`}
		>
			Create an account
		</a>
	</aside>
{/if}
