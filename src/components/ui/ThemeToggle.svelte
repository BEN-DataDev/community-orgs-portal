<script lang="ts">
	import { Moon, Sun } from 'lucide-svelte';
	import { theme } from '$lib/theme.svelte';
</script>

<button
	type="button"
	class="btn-icon preset-tonal"
	aria-label={theme.dark ? 'Switch to light mode' : 'Switch to dark mode'}
	aria-pressed={theme.dark}
	onclick={() => theme.toggleDark()}
>
	{#if theme.dark}
		<Sun size={20} />
	{:else}
		<Moon size={20} />
	{/if}
</button>
