<script lang="ts">
	import { page } from '$app/state';
	import { Navigation } from '@skeletonlabs/skeleton-svelte';
	import { Building2, FileBarChart, Home, Icon, Shield } from 'lucide-svelte';

	interface Destination {
		href: string;
		label: string;
		icon: typeof Icon;
	}

	interface Props {
		/**
		 * `bar` on phones, `rail` on tablets, `sidebar` on desktop. Skeleton 5's
		 * Navigation is headless — it emits `data-scope`/`data-part`/`data-layout`
		 * and no styling at all — so every class below is ours to supply.
		 */
		layout: 'bar' | 'rail' | 'sidebar';
	}

	let { layout }: Props = $props();

	const destinations: Destination[] = [
		{ href: '/', label: 'Home', icon: Home },
		{ href: '/organisations', label: 'Organisations', icon: Building2 },
		{ href: '/reports', label: 'Reports', icon: FileBarChart },
		{ href: '/admin', label: 'Admin', icon: Shield }
	];

	/**
	 * `/` would otherwise prefix-match every route, so it has to match exactly.
	 * Everything else marks its whole subtree active, keeping the parent
	 * highlighted on e.g. `/organisations/{id}/contact`.
	 */
	function isActive(href: string, pathname: string): boolean {
		return href === '/' ? pathname === '/' : pathname === href || pathname.startsWith(`${href}/`);
	}

	const rootClass = $derived(
		{
			// Bottom bar. The safe-area padding keeps it clear of the iOS home indicator.
			bar: 'fixed inset-x-0 bottom-0 z-50 border-t border-surface-200-800 bg-surface-50-950 pb-[env(safe-area-inset-bottom)]',
			rail: 'sticky top-0 h-dvh w-20 shrink-0 border-r border-surface-200-800 bg-surface-50-950',
			sidebar: 'sticky top-0 h-dvh w-64 shrink-0 border-r border-surface-200-800 bg-surface-50-950'
		}[layout]
	);

	const menuClass = $derived(
		layout === 'bar' ? 'grid auto-cols-fr grid-flow-col' : 'flex flex-col gap-1 p-2 overflow-y-auto'
	);

	const anchorClass = $derived(
		{
			bar: 'flex flex-col items-center justify-center gap-1 px-1 py-2 text-[0.6875rem]',
			rail: 'flex flex-col items-center justify-center gap-1 rounded-base px-1 py-2 text-[0.6875rem]',
			sidebar: 'flex items-center gap-3 rounded-base px-3 py-2 text-sm'
		}[layout]
	);
</script>

<Navigation {layout} class={rootClass} aria-label="Main">
	<Navigation.Content class={layout === 'bar' ? '' : 'flex h-full flex-col'}>
		<Navigation.Menu class={menuClass}>
			{#each destinations as destination (destination.href)}
				{@const active = isActive(destination.href, page.url.pathname)}
				<Navigation.TriggerAnchor
					href={destination.href}
					class="{anchorClass} {active
						? 'preset-filled-primary-500'
						: 'hover:preset-tonal'} transition-colors"
					aria-current={active ? 'page' : undefined}
				>
					<destination.icon size={layout === 'sidebar' ? 18 : 20} aria-hidden="true" />
					<Navigation.TriggerText
						class={layout === 'bar' || layout === 'rail' ? 'leading-tight' : ''}
					>
						{destination.label}
					</Navigation.TriggerText>
				</Navigation.TriggerAnchor>
			{/each}
		</Navigation.Menu>
	</Navigation.Content>
</Navigation>
