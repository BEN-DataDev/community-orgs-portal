<script lang="ts">
	import { invalidate } from '$app/navigation';
	import { onMount } from 'svelte';

	import { AppBar } from '@skeletonlabs/skeleton-svelte';

	import Paperclip from 'lucide-svelte/icons/paperclip';
	import Calendar from 'lucide-svelte/icons/calendar';
	import CircleUser from 'lucide-svelte/icons/circle-user';
	import Menu from 'lucide-svelte/icons/menu';

	import '../app.css';
	import ThemeToggle from '$components/ui/ThemeToggle.svelte';
	import ThemeSelector from '$components/ui/ThemeSelector.svelte';
	import AppBarDropdown from '$components/ui/navigation/AppBarDropdown.svelte';

	let { data, children } = $props();
	let { session, supabase, user } = $derived(data);

	onMount(() => {
		const darkMode = localStorage.getItem('darkMode') === 'true';
		document.documentElement.classList.toggle('dark', darkMode);
		const { data } = supabase.auth.onAuthStateChange((_, newSession) => {
			if (newSession?.expires_at !== session?.expires_at) {
				invalidate('supabase:auth');
			}
		});

		return () => data.subscription.unsubscribe();
	});
</script>

<AppBar headlineClasses="sm:hidden" centerClasses="hidden sm:block">
	{#snippet lead()}
		<a
			class="hidden sm:flex sm:items-end"
			aria-label="CII logo"
			style="padding-left: 40px; padding-top: 10px; padding-bottom: 10px;"
			href="https://resiliencehub.org.au/"
		>
			<img width="60" height="60" src="/images/Logo.png" alt="CII logo" />
			<span class="ml-2 translate-y-[5px] text-xl text-[#092750]"
				>Community Information<br /> Infrastructure</span
			>
		</a>
	{/snippet}
	{#snippet trail()}
		<ThemeSelector />
		<ThemeToggle />
		<AppBarDropdown />
		<button type="button" class="btn btn-sm preset-filled">Medium</button>
		<button type="button" class="btn btn-sm preset-filled">Medium1</button>
		<button type="button" class="btn btn-sm preset-filled">Medium2</button>
		<button type="button" class="btn btn-sm preset-filled">Medium3</button>
		<div class="hidden space-x-4 sm:flex">
			<Paperclip size={20} />
			<Calendar size={20} />
			<CircleUser size={20} />
		</div>
		<div class="block sm:hidden">
			<Menu size={20} />
		</div>
	{/snippet}
	{#snippet headline()}
		<h1 class="h1">Title</h1>
	{/snippet}
	<!-- <span><h1 class="h1">Title</h1></span> -->
	{#snippet children()}
		<h1 class="h1 text-3xl">Title</h1>
	{/snippet}
</AppBar>

<!-- <Navbar {toggleNav} {closeNav} {navStatus} breakPoint="md">
	{#snippet brand()}
		<NavBrand siteName="Community Information Infrastructure">
			<img width="30" src="/images/Logo.png" alt="cii logo" />
		</NavBrand>
	{/snippet}

	<NavUl>
		<NavLi href="/">Home</NavLi>
		<NavLi href="/components/navbar">Navbar</NavLi>
		<NavLi href="/components/footer">Footer</NavLi>
	</NavUl>
</Navbar> -->
<!-- <div class="flex min-h-screen w-full flex-col"> -->
<!-- <Navbar
		{toggleNav}
		{closeNav}
		{navStatus}
		breakPoint="md"
		navClass="bg-fill-300 dark:bg-fill-800 border-b border-surface-200 dark:border-surface-700"
	>
		{#snippet brand()}
			<NavBrand
				siteName="Community Information Infrastructure"
				spanClass="md:text-4xl text-tertiary-800 dark:text-tertiary-200"
			>
				<img width="60" src="/images/Logo.png" alt="cii logo" />
			</NavBrand>
		{/snippet}
		{#snippet navSlotBlock()}
			<div class="flex items-center space-x-1 md:order-2">
				<Darkmode />
				{#if !user}
					<Button href="/auth/signin" size="sm">Sign In</Button>
				{:else}
					<!-- {#if avatarSrc}
						<Avatar
							class="cursor-pointer"
							onclick={dropdownUser.toggle}
							src={user?.user_metadata?.picture}
							dot={{ color: 'green' }}
						/>
					{:else}
						<Avatar border dot={{ color: 'green' }} class="cursor-pointer" />
					{/if} -->
<!-- <div class="relative"> -->
<!-- <Dropdown
							dropdownStatus={dropdownUserStatus}
							closeDropdown={closeDropdownUser}
							params={{ y: 0, duration: 200, easing: sineIn }}
							class="dropdown-content absolute right-0 top-[14px] border border-surface-200 bg-fill-50 dark:border-surface-700 dark:bg-fill-800"
						>
							<DropdownHeader class="bg-fill-100 px-4 py-2 dark:bg-fill-700">
								<span class="block text-sm text-text-900 dark:text-text-50"
									>{user.user_metadata?.full_name || 'User'}</span
								>
								<span class="block truncate text-sm font-medium text-text-600 dark:text-text-300"
									>{user.email}</span
								>
							</DropdownHeader>
							<DropdownUl>
								<DropdownLi
									href="/users/[{user.id}]/profile"
									class="cursor-pointer hover:text-primary-600 dark:hover:text-primary-400"
									>My Profile</DropdownLi
								>
								<DropdownLi
									href="/users/[{user.id}]/dashboard"
									class="cursor-pointer hover:text-primary-600 dark:hover:text-primary-400"
									>My Dashboard</DropdownLi
								>
								<DropdownDivider />
								<DropdownLi
									href="/auth/signout"
									class="cursor-pointer hover:text-primary-600 dark:hover:text-primary-400"
									>Sign Out</DropdownLi
								>
							</DropdownUl>
							<DropdownFooter
								class="bg-fill-100 px-4 py-2 text-sm hover:bg-gray-100 dark:bg-fill-700 dark:hover:bg-gray-600"
								><span class="font-medium text-text-600 dark:text-text-300"
									>Role:
								</span>{' '}{user.role}
							</DropdownFooter>
						</Dropdown> -->
<!-- </div>
				{/if}
			</div>
		{/snippet}
		<NavUl class="flex h-10 items-center justify-center text-secondary-800 dark:text-secondary-100">
			<NavLi href="/" class="pl-4 hover:text-primary-600 dark:hover:text-primary-400">Home</NavLi>
			{#if user}
				<NavLi
					href="/users/[{user.id}]/dashboard"
					class="hover:text-primary-600 dark:hover:text-primary-400">My Account</NavLi
				>
				<NavLi href="/communities" class="pr-4 hover:text-primary-600 dark:hover:text-primary-400"
					>Communities</NavLi
				>
				<NavLi href="/projects" class="pr-4 hover:text-primary-600 dark:hover:text-primary-400"
					>Projects</NavLi
				>
				<NavLi href="/users" class="pr-4 hover:text-primary-600 dark:hover:text-primary-400"
					>Users</NavLi
				> -->
<!-- {/if} -->
<!-- <NavLi
				class="cursor-pointer hover:text-primary-600 dark:hover:text-primary-400"
				onclick={toggleProjects}
			>
				<span bind:this={projectsNavLi}>
					My Projects<ChevronDownOutline
						class="ms-2 inline h-6 w-6  text-primary-600 dark:text-primary-400"
					/>
				</span>
			</NavLi> -->
<!-- </NavUl> -->
<!-- </Navbar> -->
<!-- <div class="relative">
		<MegaMenu
			items={projects}
			dropdownStatus={megaStatus}
			class="absolute top-[60px] w-[450px] bg-fill-100 dark:bg-fill-800"
			style="left: {megaMenuLeft};"
		>
			{#snippet children(prop)}
				<a
					href={prop.item.href}
					class="flex items-center text-text-700 hover:text-primary-600 dark:text-text-200 dark:hover:text-primary-400"
				>
					<prop.item.Icon class="me-2 h-4 w-4" />
					{prop.item.name}
				</a>
			{/snippet}
		</MegaMenu>
	</div> -->
<main class="flex min-h-screen w-full flex-1 flex-col overflow-auto">
	{@render children?.()}
</main>
<!-- <Footer
		class="border-t border-surface-200 bg-fill-100 py-3 shadow-none md:py-3 dark:border-surface-700 dark:bg-fill-800"
		footerType="logo"
	>
		<div class="sm:flex sm:items-center sm:justify-between">
			<FooterCopyright
				href="/"
				class="text-text-700 dark:text-text-300"
				by="Community Information Infrastructure"
				year={2024}
			/>
			<FooterUl
				class="mt-3 flex flex-wrap items-center text-sm text-text-800 sm:mt-0 dark:text-text-300"
			>
				<FooterLi href="/" class="hover:text-primary-600 dark:hover:text-primary-400"
					>About</FooterLi
				>
				<FooterLi href="/" class="hover:text-primary-600 dark:hover:text-primary-400"
					>Privacy Policy</FooterLi
				>
				<FooterLi href="/" class="hover:text-primary-600 dark:hover:text-primary-400"
					>Licensing</FooterLi
				>
				<FooterLi href="/" class="hover:text-primary-600 dark:hover:text-primary-400"
					>Contact</FooterLi
				>
			</FooterUl>
		</div>
	</Footer> -->
<!-- </div> -->
