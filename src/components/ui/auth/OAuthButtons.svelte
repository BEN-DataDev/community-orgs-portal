<script lang="ts">
	import { OAUTH_PROVIDERS } from '$lib/auth/providers';
	import ProviderIcon from './ProviderIcon.svelte';

	interface Props {
		/** "Sign in" on the sign-in page, "Sign up" on registration. */
		verb?: string;
		redirectTo?: string;
		disabled?: boolean;
	}

	let { verb = 'Sign in', redirectTo = '', disabled = false }: Props = $props();
</script>

<!--
	One form per provider, each posting to `/auth/oauth/<slug>`.

	Deliberately plain forms without `use:enhance`. The response is a redirect to
	the provider's own domain, and enhance hands redirects to `goto()`, which
	cannot navigate off-site — the flow would silently do nothing.
-->
<div class="space-y-2">
	{#each OAUTH_PROVIDERS as provider (provider.slug)}
		<form method="POST" action="/auth/oauth/{provider.slug}">
			<input type="hidden" name="redirectTo" value={redirectTo} />
			<button type="submit" class="btn preset-tonal min-w-full" {disabled}>
				<ProviderIcon provider={provider.slug} />
				<span>{verb} with {provider.label}</span>
			</button>
		</form>
	{/each}
</div>
