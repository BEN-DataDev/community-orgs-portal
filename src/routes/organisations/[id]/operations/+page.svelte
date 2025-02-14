<script lang="ts">
	import OperationsForm from '$components/forms/OperationsForm.svelte';
	import OperationsMap from '$components/maps/OperationsMap.svelte';

	let { data } = $props();
	let { operationalInfo } = $derived(data);
	let isEditing = $state(false);
</script>

<div class="container mx-auto px-4 py-8">
	<div class="mb-6 flex items-center justify-between">
		<div>
			<h1 class="h1">Operational Information</h1>
			<p class="text-surface-600-300-token">{operationalInfo.organisations.legal_name}</p>
		</div>
		<button class="variant-filled btn" onclick={() => (isEditing = !isEditing)}>
			{isEditing ? 'Cancel' : 'Edit Operations'}
		</button>
	</div>

	{#if isEditing}
		<OperationsForm {operationalInfo} onSave={() => (isEditing = false)} />
	{:else}
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
			<div class="variant-filled card">
				<header class="card-header">Staff & Volunteers</header>
				<section class="space-y-2 p-4">
					<p><strong>Staff Count:</strong> {operationalInfo.staff_count}</p>
					<p><strong>Volunteer Count:</strong> {operationalInfo.volunteer_count}</p>
				</section>
			</div>

			<div class="variant-filled card">
				<header class="card-header">Operating Hours</header>
				<section class="p-4">
					{#each operationalInfo.operational_hours as hours}
						<div class="flex justify-between py-1">
							<span class="font-medium">{hours.day}</span>
							<span>{hours.open} - {hours.close}</span>
						</div>
					{/each}
				</section>
			</div>

			<div class="variant-filled card">
				<header class="card-header">Service Areas</header>
				<section class="p-4">
					<ul class="space-y-1">
						{#each operationalInfo.service_areas as area}
							<li>{area}</li>
						{/each}
					</ul>
				</section>
			</div>

			<div class="lg:col-span-3">
				<div class="variant-filled card">
					<header class="card-header">Locations</header>
					<section class="p-4">
						<div class="grid grid-cols-1 gap-4 md:grid-cols-2">
							<div class="space-y-4">
								{#each operationalInfo.locations as location}
									<div class="variant-ghost card p-4">
										<h3 class="font-medium">{location.name}</h3>
										<p class="text-surface-600-300-token text-sm">{location.address}</p>
										<p class="text-surface-500-400-token text-sm">{location.type}</p>
									</div>
								{/each}
							</div>
							<OperationsMap locations={operationalInfo.locations} />
						</div>
					</section>
				</div>
			</div>
		</div>
	{/if}
</div>
