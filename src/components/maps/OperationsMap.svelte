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

	let mapContainer: HTMLDivElement;
	let map: maplibregl.Map;

	onMount(() => {
		if (!mapContainer) return;

		const initMap = async () => {
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
		};

		initMap();

		return () => {
			if (map) {
				map.remove();
			}
		};
	});

	function createMarkerElement(location: (typeof locations)[0]): HTMLElement {
		const colors: { [key: string]: string } = {
			'Head Office': 'bg-blue-500',
			Branch: 'bg-green-500',
			'Service Center': 'bg-purple-500'
		};

		const el = document.createElement('div');
		el.className = `w-8 h-8 rounded-full ${colors[location.type] || 'bg-gray-500'} border-2 border-white shadow-lg cursor-pointer`;
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
