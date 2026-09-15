<script lang="ts">
	import { theme, type ColorMode } from '$lib/theme.svelte';
	const modes: ColorMode[] = ['light', 'dark', 'system'];
</script>

<fieldset class="space-y-2">
	<legend class="font-medium">Appearance</legend>
	<div class="flex flex-wrap gap-2">
		{#each modes as mode (mode)}
			<label class="btn preset-tonal cursor-pointer capitalize">
				<input
					type="radio"
					name="appearance"
					value={mode}
					checked={theme.mode === mode}
					onchange={() => theme.setMode(mode)}
				/>
				{mode}
			</label>
		{/each}
	</div>
	<p class="text-surface-600-400 text-sm">
		Saved on this device. System follows your device’s appearance.
	</p>
</fieldset>
