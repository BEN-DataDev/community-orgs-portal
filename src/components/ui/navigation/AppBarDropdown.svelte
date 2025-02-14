<script lang="ts">
	let isOpen = $state(false);

	function toggleDropdown() {
		isOpen = !isOpen;
	}

	// Close dropdown when clicking outside
	function handleClickOutside(event: MouseEvent) {
		const target = event.target as HTMLElement;
		if (!target.closest('.dropdown-container')) {
			isOpen = false;
		}
	}
</script>

<svelte:window onclick={handleClickOutside} />

<div class="dropdown-container relative">
	<button class="variant-filled btn" onclick={toggleDropdown}> Menu </button>

	{#if isOpen}
		<div
			class="absolute right-0 mt-2 w-48 rounded-md bg-white shadow-lg ring-1 ring-black ring-opacity-5 dark:bg-gray-800"
		>
			<div class="py-1">
				<a href="/" class="block px-4 py-2 text-sm hover:bg-gray-100 dark:hover:bg-gray-700">
					Home
				</a>
				<a href="/about" class="block px-4 py-2 text-sm hover:bg-gray-100 dark:hover:bg-gray-700">
					About
				</a>
				<a
					href="/settings"
					class="block px-4 py-2 text-sm hover:bg-gray-100 dark:hover:bg-gray-700"
				>
					Settings
				</a>
			</div>
		</div>
		<!-- <div class="variant-filled card absolute right-0 mt-2 w-48">
			<div class="space-y-2 p-4">
				<a href="/" class="variant-ghost btn w-full justify-start"> Home </a>
				<a href="/about" class="variant-ghost btn w-full justify-start"> About </a>
				<a href="/settings" class="variant-ghost btn w-full justify-start"> Settings </a>
			</div>
		</div> -->
	{/if}
</div>
