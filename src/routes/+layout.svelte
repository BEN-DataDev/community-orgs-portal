<script lang="ts">
	import { resolve } from '$app/paths';
	import { invalidate } from '$app/navigation';
	import { onMount } from 'svelte';

	import { AppBar } from '@skeletonlabs/skeleton-svelte';

	import '../app.css';
	import AppNavigation from '$components/layout/AppNavigation.svelte';
	import ThemeToggle from '$components/ui/ThemeToggle.svelte';
	import { minWidth } from '$lib/media.svelte';
	import { theme } from '$lib/theme.svelte';

	let { data, children } = $props();
	let { session, supabase, user, isSiteAdmin } = $derived(data);

	/**
	 * Navigation takes a different *prop* per breakpoint rather than different
	 * classes, so the breakpoint has to be reactive state. Both default to
	 * `false` so SSR renders the mobile layout and widens on hydration.
	 */
	const isTablet = minWidth('md');
	const isDesktop = minWidth('lg');

	const navLayout = $derived(isDesktop.matches ? 'sidebar' : isTablet.matches ? 'rail' : 'bar');

	onMount(() => {
		const disposeTheme = theme.init();
		const disposeTablet = isTablet.subscribe();
		const disposeDesktop = isDesktop.subscribe();

		const { data: authListener } = supabase.auth.onAuthStateChange((_, newSession) => {
			if (newSession?.expires_at !== session?.expires_at) {
				invalidate('supabase:auth');
			}
		});

		return () => {
			disposeTheme();
			disposeTablet();
			disposeDesktop();
			authListener.subscription.unsubscribe();
		};
	});
</script>

<div class="flex min-h-dvh flex-col">
	<AppBar>
		<AppBar.Toolbar class="gap-2 px-4 sm:px-6 lg:px-8">
			<AppBar.Lead>
				<a class="flex items-center gap-2" aria-label="CII home" href={resolve('/')}>
					<img width="48" height="48" src="/images/Logo.png" alt="" />
					<span class="hidden text-lg leading-tight sm:block">
						Community Information<br />Infrastructure
					</span>
				</a>
			</AppBar.Lead>

			<AppBar.Trail class="flex flex-wrap items-center justify-end gap-2">
				{#if user}
					<a class="btn btn-sm preset-tonal" href={resolve('/auth/signout')}>Sign out</a>
				{:else}
					<a class="btn btn-sm preset-filled" href={resolve('/auth/signin')}>Sign in</a>
				{/if}
				<ThemeToggle />
			</AppBar.Trail>
		</AppBar.Toolbar>
	</AppBar>

	<div class="flex flex-1 flex-col md:flex-row">
		{#if user}
			<AppNavigation layout={navLayout} {isSiteAdmin} />
		{/if}

		<!--
			`min-w-0` lets wide children (tables, maps, the d3 timeline) shrink
			inside the flex row instead of forcing the page to scroll sideways.
			The bottom padding clears the fixed mobile bar.
		-->
		<main class="flex min-w-0 flex-1 flex-col {user ? 'pb-20 md:pb-0' : ''}">
			<div class="mx-auto w-full max-w-7xl flex-1 px-4 py-6 sm:px-6 lg:px-8">
				{@render children?.()}
			</div>
		</main>
	</div>

	<footer class="border-surface-200-800 border-t p-4 text-sm {user ? 'pb-20 md:pb-4' : ''}">
		<div class="mx-auto flex max-w-7xl flex-wrap justify-between gap-2 px-4 sm:px-6 lg:px-8">
			<span>Community Information Infrastructure</span>
			<a class="hover:underline" href="https://resiliencehub.org.au/">resiliencehub.org.au</a>
		</div>
	</footer>
</div>
