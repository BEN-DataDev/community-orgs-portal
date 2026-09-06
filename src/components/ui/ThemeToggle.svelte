<script lang="ts">
	import { Monitor, Moon, Sun } from 'lucide-svelte';
	import { theme, type ColorMode } from '$lib/theme.svelte';

	/**
	 * Cycles `system → light → dark`. The label names the state the button will
	 * move to, which is what a screen reader user needs to hear before acting.
	 */
	const NEXT_LABEL: Record<ColorMode, string> = {
		system: 'Switch to light mode',
		light: 'Switch to dark mode',
		dark: 'Use system colour mode'
	};
</script>

<button
	type="button"
	class="btn-icon preset-tonal"
	aria-label={NEXT_LABEL[theme.mode]}
	title={NEXT_LABEL[theme.mode]}
	onclick={() => theme.cycle()}
>
	{#if theme.mode === 'system'}
		<Monitor size={20} />
	{:else if theme.mode === 'dark'}
		<Moon size={20} />
	{:else}
		<Sun size={20} />
	{/if}
</button>
