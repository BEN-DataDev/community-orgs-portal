<script lang="ts">
	import { onMount } from 'svelte';

	const themes = [
		{ value: 'concord', name: 'Concord' },
		{ value: 'legacy', name: 'Legacy' },
		{ value: 'mona', name: 'Mona' },
		{ value: 'rocket', name: 'Rocket' },
		{ value: 'seafoam', name: 'Seafoam' },
		{ value: 'vox', name: 'Vox' },
		{ value: 'wintry', name: 'Wintry' },
		{ value: 'cii-theme', name: 'CII Theme' }
	];

	let currentTheme: string;

	onMount(() => {
		currentTheme = localStorage.getItem('theme') || 'concord';
		setTheme(currentTheme);
	});

	function setTheme(theme: string) {
		currentTheme = theme;
		document.body.setAttribute('data-theme', theme);
		localStorage.setItem('theme', theme);
	}
</script>

<div class="flex items-center space-x-2">
	<select
		class="variant-filled select"
		bind:value={currentTheme}
		on:change={() => setTheme(currentTheme)}
	>
		{#each themes as theme}
			<option value={theme.value}>{theme.name}</option>
		{/each}
	</select>
</div>
