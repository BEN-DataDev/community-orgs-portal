<script lang="ts">
	import { invalidate } from '$app/navigation';
	import { onMount } from 'svelte';

	import { AppBar } from '@skeletonlabs/skeleton-svelte';

	import '../app.css';
	import ThemeToggle from '$components/ui/ThemeToggle.svelte';
	import { theme } from '$lib/theme.svelte';

	let { data, children } = $props();
	let { session, supabase, user } = $derived(data);

	onMount(() => {
		const disposeTheme = theme.init();

		const { data: authListener } = supabase.auth.onAuthStateChange((_, newSession) => {
			if (newSession?.expires_at !== session?.expires_at) {
				invalidate('supabase:auth');
			}
		});

		return () => {
			disposeTheme();
			authListener.subscription.unsubscribe();
		};
	});
</script>

<AppBar>
	<AppBar.Toolbar>
		<AppBar.Lead>
			<a class="flex items-center gap-2" aria-label="CII home" href="/">
				<img width="48" height="48" src="/images/Logo.png" alt="" />
				<span class="hidden text-lg leading-tight sm:block">
					Community Information<br />Infrastructure
				</span>
			</a>
		</AppBar.Lead>

		<AppBar.Trail>
			{#if user}
				<a class="btn btn-sm preset-filled" href="/organisations">Organisations</a>
				<a class="btn btn-sm preset-tonal" href="/auth/signout">Sign out</a>
			{:else}
				<a class="btn btn-sm preset-filled" href="/auth/signin">Sign in</a>
			{/if}
			<ThemeToggle />
		</AppBar.Trail>
	</AppBar.Toolbar>
</AppBar>

<main class="flex min-h-screen w-full flex-1 flex-col overflow-auto">
	{@render children?.()}
</main>

<footer class="border-t p-4 text-sm">
	<div class="container mx-auto flex flex-wrap justify-between gap-2">
		<span>Community Information Infrastructure</span>
		<a class="hover:underline" href="https://resiliencehub.org.au/">resiliencehub.org.au</a>
	</div>
</footer>
