<script lang="ts">
	import { Avatar, Menu, Portal } from '@skeletonlabs/skeleton-svelte';
	import {
		Check,
		ChevronDown,
		UserRound,
		Settings,
		ShieldCheck,
		Users,
		LogOut,
		Monitor,
		Moon,
		Sun
	} from 'lucide-svelte';
	import type { HTMLAnchorAttributes } from 'svelte/elements';
	import type { AccountAvatar } from '$lib/avatar';
	import type { SessionAal } from '$lib/auth/session';
	import type { User } from '@supabase/supabase-js';
	import { resolve } from '$app/paths';
	import { accessLabel, displayName, type Membership } from '$lib/account';
	import { theme, type ColorMode } from '$lib/theme.svelte';

	let {
		user,
		isAnonymous,
		isSiteAdmin,
		aal,
		memberships,
		avatar
	}: {
		avatar: AccountAvatar | null;
		user: User | null;
		isAnonymous: boolean;
		isSiteAdmin: boolean;
		aal: SessionAal | null;
		memberships: Membership[] | null;
	} = $props();
	const signedIn = $derived(!!user && !isAnonymous);
	const name = $derived(signedIn ? displayName(user) : isAnonymous ? 'Guest' : 'Appearance');
	const status = $derived(isAnonymous ? 'Guest' : accessLabel(memberships));
	const initials = $derived(
		name
			.split(/\s+/)
			.slice(0, 2)
			.map((part) => Array.from(part)[0])
			.join('')
			.toUpperCase()
	);
	const photo = $derived(signedIn ? avatar?.url : null);
	const modes: { value: ColorMode; label: string; icon: typeof Sun }[] = [
		{ value: 'light', label: 'Light', icon: Sun },
		{ value: 'dark', label: 'Dark', icon: Moon },
		{ value: 'system', label: 'System', icon: Monitor }
	];
	const links = $derived(
		signedIn
			? [
					{ href: resolve('/account/settings'), label: 'Settings', icon: Settings },
					{ href: resolve('/account/security'), label: 'Security & sign-in', icon: ShieldCheck },
					{ href: `${resolve('/account/settings')}#access`, label: 'My access', icon: Users },
					...(isSiteAdmin
						? [{ href: resolve('/admin'), label: 'Administration', icon: ShieldCheck }]
						: [])
				]
			: isAnonymous
				? [{ href: resolve('/auth/signup'), label: 'Create an account', icon: UserRound }]
				: []
	);
	// Skeleton 5.0.1 types custom item elements as divs; these items render anchors.
	const itemClass =
		'flex min-h-11 cursor-pointer items-center gap-3 rounded-base px-3 py-2 text-sm outline-none data-[highlighted]:preset-tonal-primary';
</script>

<Menu positioning={{ placement: 'bottom-end', gutter: 8 }}>
	<Menu.Trigger
		class="focus-visible:outline-primary-500 flex min-h-11 items-center gap-2 rounded-full p-1 focus-visible:outline-2 focus-visible:outline-offset-2"
		aria-label={user ? `Account menu for ${name}: ${status}` : 'Appearance menu'}
	>
		<span class="relative">
			<Avatar class="preset-tonal-primary size-10 overflow-hidden rounded-full">
				{#if photo}<Avatar.Image
						src={photo}
						alt=""
						referrerpolicy="no-referrer"
						class="size-full object-cover"
					/>{/if}
				<Avatar.Fallback class="flex size-full items-center justify-center text-sm font-semibold">
					{#if signedIn}{initials}{:else if isAnonymous}<UserRound
							size={20}
							aria-hidden="true"
						/>{:else}<Monitor size={20} aria-hidden="true" />{/if}
				</Avatar.Fallback>
			</Avatar>
			{#if user}<span
					aria-hidden="true"
					class="border-surface-50-950 absolute -right-0.5 -bottom-0.5 size-3 rounded-full border-2 {isAnonymous ||
					memberships === null
						? 'bg-surface-500'
						: isSiteAdmin
							? 'bg-primary-500'
							: 'bg-success-500'}"
				></span>{/if}
		</span>
		<ChevronDown size={14} aria-hidden="true" />
	</Menu.Trigger>
	<Portal>
		<Menu.Positioner class="z-[60]">
			<Menu.Content
				class="rounded-container border-surface-200-800 bg-surface-50-950 max-h-[calc(100dvh-6rem)] w-76 max-w-[calc(100vw-2rem)] overflow-y-auto border p-2 shadow-xl outline-none"
			>
				{#if user}
					<div class="space-y-1 px-3 py-3">
						<p class="font-semibold break-words">{name}</p>
						{#if signedIn}<p class="text-surface-600-400 text-sm break-all">
								{user.email ?? 'No email address'}
							</p>{/if}
						<span class="badge preset-tonal">{status}</span>
						{#if signedIn && aal?.currentLevel === 'aal2'}<p class="text-success-700-300 text-sm">
								Two-factor verified
							</p>
						{:else if signedIn && aal?.nextLevel === 'aal2'}<p class="text-warning-700-300 text-sm">
								Verification required
							</p>{/if}
					</div>
					<Menu.Separator class="border-surface-200-800 my-1 border-t" />
				{/if}
				{#each links as link (link.href)}
					<Menu.Item value={link.href}>
						{#snippet element(attributes)}
							<a
								{...attributes as unknown as HTMLAnchorAttributes}
								href={link.href}
								class={itemClass}><link.icon size={18} aria-hidden="true" />{link.label}</a
							>
						{/snippet}
					</Menu.Item>
				{/each}
				<Menu.ItemGroup>
					<Menu.ItemGroupLabel class="text-surface-600-400 px-3 pt-3 pb-1 text-xs font-semibold"
						>Appearance</Menu.ItemGroupLabel
					>
					{#each modes as mode (mode.value)}
						<Menu.OptionItem
							class={itemClass}
							value={mode.value}
							type="radio"
							checked={theme.mode === mode.value}
							closeOnSelect={false}
							onCheckedChange={(checked) => {
								if (checked) theme.setMode(mode.value);
							}}
						>
							<mode.icon size={18} aria-hidden="true" />
							<Menu.ItemText class="flex-1">{mode.label}</Menu.ItemText>
							<Menu.ItemIndicator class="hidden data-[state=checked]:block"
								><Check size={16} aria-hidden="true" /></Menu.ItemIndicator
							>
						</Menu.OptionItem>
					{/each}
				</Menu.ItemGroup>
				{#if user}
					<Menu.Separator class="border-surface-200-800 my-1 border-t" />
					<Menu.Item value="signout">
						{#snippet element(attributes)}
							<a
								{...attributes as unknown as HTMLAnchorAttributes}
								href={resolve('/auth/signout')}
								class={itemClass}
								><LogOut size={18} aria-hidden="true" />{isAnonymous
									? 'Leave guest mode'
									: 'Sign out'}</a
							>
						{/snippet}
					</Menu.Item>
				{/if}
			</Menu.Content>
		</Menu.Positioner>
	</Portal>
</Menu>
