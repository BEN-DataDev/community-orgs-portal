/src/routes/organisations/[id]/operations/+page.server.ts

```ts
import { supabase } from '$lib/services/supabase';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ params }) => {
	const { data: operationalInfo } = await supabase
		.from('operational_details')
		.select(
			`
            *,
            organisations (
                legal_name,
                trading_name
            ),
            locations (
                id,
                name,
                address,
                type
            ),
            staff_count,
            volunteer_count,
            operational_hours,
            service_areas
        `
		)
		.eq('org_id', params.id)
		.single();

	return { operationalInfo };
};

export const actions: Actions = {
	updateOperations: async ({ request }) => {
		const formData = await request.formData();
		const { orgId, ...operationsData } = Object.fromEntries(formData);

		const { data, error } = await supabase
			.from('operational_details')
			.upsert({
				org_id: orgId,
				...operationsData
			})
			.select();

		return { success: !error, data };
	}
};
```

/src/routes/organisations/[id]/operations/+page.svelte

```svelte
<script lang="ts">
	import { enhance } from '$app/forms';
	import { Button, Card } from '$lib/components/common';
	import OperationsForm from '$lib/components/forms/OperationsForm.svelte';
	import LocationMap from '$lib/components/maps/LocationMap.svelte';

	let { data } = $props();

	let { operationalInfo } = $derived(data);
	let isEditing = $state(false);
</script>

<div class="container mx-auto px-4 py-8">
	<div class="mb-6 flex items-center justify-between">
		<div>
			<h1 class="text-2xl font-bold">Operational Information</h1>
			<p class="text-gray-600">{operationalInfo.organisations.legal_name}</p>
		</div>
		<Button on:click={() => (isEditing = !isEditing)}>
			{isEditing ? 'Cancel' : 'Edit Operations'}
		</Button>
	</div>

	{#if isEditing}
		<OperationsForm {operationalInfo} on:save={() => (isEditing = false)} />
	{:else}
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
			<Card title="Staff & Volunteers">
				<div class="space-y-2">
					<p><strong>Staff Count:</strong> {operationalInfo.staff_count}</p>
					<p><strong>Volunteer Count:</strong> {operationalInfo.volunteer_count}</p>
				</div>
			</Card>

			<Card title="Operating Hours">
				{#each operationalInfo.operational_hours as hours}
					<div class="flex justify-between py-1">
						<span class="font-medium">{hours.day}</span>
						<span>{hours.open} - {hours.close}</span>
					</div>
				{/each}
			</Card>

			<Card title="Service Areas">
				<ul class="space-y-1">
					{#each operationalInfo.service_areas as area}
						<li>{area}</li>
					{/each}
				</ul>
			</Card>

			<div class="lg:col-span-3">
				<Card title="Locations">
					<div class="grid grid-cols-1 gap-4 md:grid-cols-2">
						<div class="space-y-4">
							{#each operationalInfo.locations as location}
								<div class="rounded border p-4">
									<h3 class="font-medium">{location.name}</h3>
									<p class="text-sm text-gray-600">{location.address}</p>
									<p class="text-sm text-gray-500">{location.type}</p>
								</div>
							{/each}
						</div>
						<LocationMap locations={operationalInfo.locations} />
					</div>
				</Card>
			</div>
		</div>
	{/if}
</div>
```

OperationsMap.svelte

```svelte
<script lang="ts">
	import { onMount } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';

	interface Props {
		locations: Array<{
			name: string;
			address: string;
			type: string;
			coordinates?: [number, number];
		}>;
	}

	let { locations }: Props = $props();

	let mapContainer: HTMLDivElement = $state();
	let map: maplibregl.Map;

	onMount(async () => {
		// Initialize map with OpenStreetMap style
		map = new maplibregl.Map({
			container: mapContainer,
			style:
				'https://api.maptiler.com/maps/basic/style.json?key=' + import.meta.env.VITE_MAPTILER_KEY,
			center: locations[0]?.coordinates || [151.2093, -33.8688], // Sydney default
			zoom: 10
		});

		// Get coordinates for locations without them
		const locationsWithCoords = await Promise.all(
			locations.map(async (location) => {
				if (!location.coordinates) {
					const coords = await geocodeAddress(location.address);
					return { ...location, coordinates: coords };
				}
				return location;
			})
		);

		// Add markers
		locationsWithCoords.forEach((location) => {
			if (location.coordinates) {
				const markerElement = createMarkerElement(location);
				new maplibregl.Marker(markerElement)
					.setLngLat(location.coordinates)
					.setPopup(
						new maplibregl.Popup({ offset: 25 }).setHTML(`
                                <h3 class="font-medium">${location.name}</h3>
                                <p class="text-sm">${location.type}</p>
                                <p class="text-sm text-gray-600">${location.address}</p>
                            `)
					)
					.addTo(map);
			}
		});

		// Fit bounds to show all markers
		const bounds = new maplibregl.LngLatBounds();
		locationsWithCoords.forEach((location) => {
			if (location.coordinates) {
				bounds.extend(location.coordinates);
			}
		});
		map.fitBounds(bounds, { padding: 50 });

		return () => map.remove();
	});

	function createMarkerElement(location: (typeof locations)[0]): HTMLElement {
		const colors = {
			'Head Office': 'bg-blue-500',
			Branch: 'bg-green-500',
			'Service Center': 'bg-purple-500'
		};

		const el = document.createElement('div');
		el.className = `w-8 h-8 rounded-full ${colors[location.type]} border-2 border-white shadow-lg cursor-pointer`;
		return el;
	}

	async function geocodeAddress(address: string): Promise<[number, number]> {
		const response = await fetch(
			`https://api.maptiler.com/geocoding/${encodeURIComponent(address)}.json?key=${import.meta.env.VITE_MAPTILER_KEY}`
		);
		const data = await response.json();
		return data.features[0]?.center || [0, 0];
	}
</script>

<div bind:this={mapContainer} class="h-[400px] w-full overflow-hidden rounded-lg shadow-md">
	{#if !import.meta.env.VITE_MAPTILER_KEY}
		<div class="flex h-full items-center justify-center bg-gray-100">
			<p class="text-gray-500">Please configure your MapTiler key</p>
		</div>
	{/if}
</div>

<style>
	:global(.maplibregl-popup) {
		max-width: 300px !important;
	}

	:global(.maplibregl-popup-content) {
		padding: 1rem !important;
	}
</style>
```

OperationsForm.svelte

```svelte
<script lang="ts">
	import { enhance } from '$app/forms';
	import { Button } from '$lib/components/common';

	interface OperationalHours {
		day: string;
		open: string;
		close: string;
	}

	interface Location {
		name: string;
		address: string;
		type: string;
	}

	interface OperationalInfo {
		org_id: string;
		staff_count: number;
		volunteer_count: number;
		locations: Location[];
		operational_hours: OperationalHours[];
		service_areas: string[];
	}

	interface Props {
		operationalInfo: OperationalInfo;
	}

	let { operationalInfo }: Props = $props();

	let locations = $state(operationalInfo.locations || []);
	let serviceAreas = $state(operationalInfo.service_areas || []);

	// Convert operational hours to a more manageable object format
	let operationalHours = $state(
		Object.fromEntries(
			['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'].map((day) => [
				day,
				{
					day,
					open: operationalInfo.operational_hours?.find((h) => h.day === day)?.open || '',
					close: operationalInfo.operational_hours?.find((h) => h.day === day)?.close || ''
				}
			])
		)
	);

	function addLocation() {
		locations = [...locations, { name: '', address: '', type: '' }];
	}

	function removeLocation(index: number) {
		locations = locations.filter((_, i) => i !== index);
	}

	function isValidTimeFormat(time: string): boolean {
		return !time || /^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$/.test(time);
	}

	function validateForm(): boolean {
		// Basic validation
		if (!operationalInfo?.org_id) return false;
		if (locations.some((loc) => !loc.name || !loc.address)) return false;

		// Validate time formats
		const hours = Object.values(operationalHours);
		if (hours.some((h) => !isValidTimeFormat(h.open) || !isValidTimeFormat(h.close))) {
			return false;
		}

		return true;
	}

	// Convert hours object back to array format before submission
	function prepareFormData(): OperationalHours[] {
		return Object.values(operationalHours);
	}

	function handleSubmit(event: SubmitEvent) {
		if (!validateForm()) {
			event.preventDefault();
			alert('Please fill in all required fields correctly');
			return;
		}
	}

	function handleServiceAreaInput(event: KeyboardEvent & { currentTarget: HTMLInputElement }) {
		if (event.key === 'Enter') {
			event.preventDefault();
			const value = event.currentTarget.value.trim();
			if (value && !serviceAreas.includes(value)) {
				serviceAreas = [...serviceAreas, value];
				event.currentTarget.value = '';
			}
		}
	}
</script>

<form
	method="POST"
	action="?/updateOperations"
	use:enhance
	onsubmit={handleSubmit}
	class="space-y-6"
>
	<input type="hidden" name="orgId" value={operationalInfo.org_id} />
	<input type="hidden" name="locations" value={JSON.stringify(locations)} />
	<input type="hidden" name="service_areas" value={JSON.stringify(serviceAreas)} />

	<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
		<div>
			<label class="mb-2 block">Staff Count</label>
			<input
				type="number"
				name="staff_count"
				min="0"
				value={operationalInfo.staff_count}
				required
				class="w-full"
			/>
		</div>

		<div>
			<label class="mb-2 block">Volunteer Count</label>
			<input
				type="number"
				name="volunteer_count"
				min="0"
				value={operationalInfo.volunteer_count}
				required
				class="w-full"
			/>
		</div>
	</div>

	<div>
		<h3 class="mb-2 font-medium">Locations</h3>
		{#each locations as location, index}
			<div class="mb-2 grid grid-cols-1 gap-4 md:grid-cols-4">
				<input
					type="text"
					bind:value={location.name}
					placeholder="Location name"
					required
					class="w-full"
				/>
				<input
					type="text"
					bind:value={location.address}
					placeholder="Address"
					required
					class="w-full"
				/>
				<select bind:value={location.type} required class="w-full">
					<option value="">Select type</option>
					<option value="Head Office">Head Office</option>
					<option value="Branch">Branch</option>
					<option value="Service Center">Service Center</option>
				</select>
				<Button type="button" variant="danger" on:click={() => removeLocation(index)}>
					Remove
				</Button>
			</div>
		{/each}
		<Button type="button" on:click={addLocation}>Add Location</Button>
	</div>

	<div>
		<h3 class="mb-2 font-medium">Operating Hours</h3>
		<input type="hidden" name="operational_hours" value={JSON.stringify(prepareFormData())} />

		{#each Object.entries(operationalHours) as [day, hours]}
			<div class="mb-2 flex items-center gap-4">
				<span class="w-24">{day}</span>
				<div class="flex items-center gap-2">
					<input type="time" bind:value={hours.open} class="w-32" />
					<span>to</span>
					<input type="time" bind:value={hours.close} class="w-32" />
				</div>
			</div>
		{/each}
	</div>

	<div>
		<h3 class="mb-2 font-medium">Service Areas</h3>
		<div class="flex flex-wrap gap-2">
			{#each serviceAreas as area, index}
				<div class="flex items-center gap-2 rounded bg-gray-100 p-2">
					<span>{area}</span>
					<button
						type="button"
						class="text-red-600 hover:text-red-800"
						onclick={() => (serviceAreas = serviceAreas.filter((_, i) => i !== index))}
					>
						×
					</button>
				</div>
			{/each}
		</div>
		<div class="mt-2">
			<input
				type="text"
				placeholder="Add new service area and press Enter"
				class="w-full"
				onkeydown={handleServiceAreaInput}
			/>
		</div>
	</div>

	<div class="flex justify-end">
		<Button type="submit">Save Changes</Button>
	</div>
</form>
```
