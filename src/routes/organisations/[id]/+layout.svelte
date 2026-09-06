<script lang="ts">
	import { page } from '$app/state';
	import { resolve } from '$app/paths';

	let { children } = $props();

	/** Always set inside the `[id]` route; the generic `page` type does not know that. */
	let orgId = $derived(page.params.id ?? '');

	/**
	 * Route IDs rather than built paths, so `resolve` type-checks each one
	 * against the actual route tree and fills in `[id]` itself.
	 */
	const sections = [
		{ route: '/organisations/[id]', label: 'Overview' },
		{ route: '/organisations/[id]/contact', label: 'Contact' },
		{ route: '/organisations/[id]/legal', label: 'Legal' },
		{ route: '/organisations/[id]/finance', label: 'Finance' },
		{ route: '/organisations/[id]/operations', label: 'Operations' },
		{ route: '/organisations/[id]/relationships', label: 'Relationships' },
		{ route: '/organisations/[id]/history', label: 'History' }
	] as const;
</script>

<!--
	Section links live here rather than on the overview page, where they used to
	sit inline: previously every section was a dead end, reachable only by going
	back to the overview first.

	These are routes, not tab panels, so this is an anchor strip styled as tabs
	rather than Skeleton's Tabs component. It scrolls horizontally on phones,
	where seven labels cannot fit.
-->
<nav aria-label="Organisation sections" class="-mx-4 mb-6 overflow-x-auto px-4 sm:mx-0 sm:px-0">
	<ul class="border-surface-200-800 flex w-max min-w-full gap-1 border-b">
		{#each sections as section (section.route)}
			{@const href = resolve(section.route, { id: orgId })}
			{@const active = page.url.pathname === href}
			<li>
				<a
					{href}
					aria-current={active ? 'page' : undefined}
					class="block border-b-2 px-3 py-2 text-sm whitespace-nowrap transition-colors {active
						? 'border-primary-500 text-primary-600-400 font-medium'
						: 'hover:border-surface-300-700 border-transparent'}"
				>
					{section.label}
				</a>
			</li>
		{/each}
	</ul>
</nav>

{@render children?.()}
