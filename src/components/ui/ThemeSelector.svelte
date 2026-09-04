<script lang="ts">
	import { THEMES, theme } from '$lib/theme.svelte';
</script>

<label class="flex items-center gap-2">
	<span class="sr-only">Theme</span>
	<select
		class="select preset-filled"
		value={theme.name}
		onchange={(event) => theme.setName(event.currentTarget.value)}
	>
		{#each THEMES as option (option.value)}
			<option value={option.value}>{option.name}</option>
		{/each}
	</select>
</label>
