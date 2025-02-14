<script lang="ts">
	import { Moon, Sun } from 'lucide-svelte';
	import { onMount } from 'svelte';

	let darkMode = false;

	onMount(() => {
		const isDarkMode = window.matchMedia('(prefers-color-scheme: dark)').matches;
		const storedDarkMode = localStorage.getItem('darkMode') === 'true';
		darkMode = storedDarkMode ?? isDarkMode;
		updateDarkMode(darkMode);
	});

	function toggleDarkMode() {
		darkMode = !darkMode;
		updateDarkMode(darkMode);
	}

	function updateDarkMode(isDark: boolean) {
		localStorage.setItem('darkMode', isDark.toString());
		document.documentElement.classList.toggle('dark', isDark);
	}
</script>

<button type="button" class="variant-ghost-surface btn" on:click={toggleDarkMode}>
	{#if darkMode}
		<Sun size={24} />
	{:else}
		<Moon size={24} />
	{/if}
</button>
