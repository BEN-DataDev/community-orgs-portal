<script lang="ts">
	import { resolve } from '$app/paths';
	import { invalidate } from '$app/navigation';
	import { onMount } from 'svelte';

	import { AppBar } from '@skeletonlabs/skeleton-svelte';

	import '../app.css';
	import AppNavigation from '$components/layout/AppNavigation.svelte';
	import GuestBanner from '$components/ui/auth/GuestBanner.svelte';
	import AccountMenu from '$components/ui/AccountMenu.svelte';
	import { minWidth } from '$lib/media.svelte';
	import { theme } from '$lib/theme.svelte';

	let { data, children } = $props();
	let { portal, session, supabase, user, isSiteAdmin, isIngestionOperator, isAnonymous } =
		$derived(data);

	/**
	 * A guest holds a session but has no account, so the navigation and the
	 * account controls have nothing to offer them — they see the public
	 * organisations and the banner inviting them to sign up.
	 */
	const signedIn = $derived(!!user && !isAnonymous);

	/**
	 * Navigation takes a different *prop* per breakpoint rather than different
	 * classes, so the breakpoint has to be reactive state. Both default to
	 * `false` so SSR renders the mobile layout and widens on hydration.
	 */
	const isTablet = minWidth('md');
	const isDesktop = minWidth('lg');

	const navLayout = $derived(isDesktop.matches ? 'sidebar' : isTablet.matches ? 'rail' : 'bar');

	$effect(() => {
		if (!data.avatar?.expiresAt) return;
		const refresh = () => {
			if (data.avatar?.expiresAt && Date.now() >= data.avatar.expiresAt - 60000)
				void invalidate('app:root');
		};
		const timer = setTimeout(refresh, Math.max(1000, data.avatar.expiresAt - Date.now() - 60000));
		window.addEventListener('focus', refresh);
		return () => {
			clearTimeout(timer);
			window.removeEventListener('focus', refresh);
		};
	});

	onMount(() => {
		const disposeTheme = theme.init();
		const disposeTablet = isTablet.subscribe();
		const disposeDesktop = isDesktop.subscribe();

		const { data: authListener } = supabase.auth.onAuthStateChange((event, newSession) => {
			if (
				event === 'USER_UPDATED' ||
				newSession?.user.id !== session?.user.id ||
				newSession?.expires_at !== session?.expires_at
			) {
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
		<AppBar.Toolbar class="flex items-center justify-between gap-2 px-4 sm:px-6 lg:px-8">
			<AppBar.Lead>
				<a
					class="flex items-center gap-2"
					aria-label={`${portal.shortName} home`}
					href={resolve('/')}
				>
					<img width="48" height="48" src={portal.logoUrl ?? '/images/Logo.png'} alt="" />
					<span class="hidden text-lg leading-tight sm:block">{portal.displayName}</span>
				</a>
			</AppBar.Lead>

			<AppBar.Trail class="flex flex-wrap items-center justify-end gap-2">
				{#if !user}
					<a class="btn btn-sm preset-filled" href={resolve('/auth/signin')}>Sign in</a>
				{/if}
				<AccountMenu
					{user}
					{isAnonymous}
					{isSiteAdmin}
					aal={data.aal}
					memberships={data.memberships}
					avatar={data.avatar}
				/>
			</AppBar.Trail>
		</AppBar.Toolbar>
	</AppBar>

	<GuestBanner />

	<div class="flex flex-1 flex-col md:flex-row">
		{#if signedIn}
			<AppNavigation {isIngestionOperator} layout={navLayout} {isSiteAdmin} />
		{/if}

		<!--
			`min-w-0` lets wide children (tables, maps, the d3 timeline) shrink
			inside the flex row instead of forcing the page to scroll sideways.
			The bottom padding clears the fixed mobile bar.
		-->
		<main class="flex min-w-0 flex-1 flex-col {signedIn ? 'pb-20 md:pb-0' : ''}">
			<div class="mx-auto w-full max-w-7xl flex-1 px-4 py-6 sm:px-6 lg:px-8">
				{@render children?.()}
			</div>
		</main>
	</div>

	<footer class="border-surface-200-800 border-t p-4 text-sm {signedIn ? 'pb-20 md:pb-4' : ''}">
		<div class="mx-auto flex max-w-7xl flex-wrap justify-between gap-2 px-4 sm:px-6 lg:px-8">
			<span>{portal.displayName}</span>
			{#if portal.sponsorUrl}
				<a class="hover:underline" href={portal.sponsorUrl}>{portal.sponsorName}</a>
			{:else}
				<span>{portal.sponsorName}</span>
			{/if}
		</div>
	</footer>
</div>
