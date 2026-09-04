<script lang="ts">
	import { onMount } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { env } from '$env/dynamic/public';

	interface Props {
		locations: Array<{
			location_id: string;
			name: string;
			address: string | null;
			location_type: string | null;
			latitude: number | null;
			longitude: number | null;
		}>;
	}

	let { locations }: Props = $props();

	let mapContainer = $state<HTMLDivElement | null>(null);
	let map: maplibregl.Map | undefined;

	/**
	 * Read through `$env/dynamic/public` rather than `import.meta.env`: this
	 * project configures the browser through `PUBLIC_`-prefixed variables, and
	 * the dynamic module tolerates the key being absent at build time.
	 */
	let mapTilerKey = $derived(env.PUBLIC_MAPTILER_KEY ?? '');

	/** Coordinates are stored on the row; nothing needs geocoding at render time. */
	let located = $derived(
		locations.filter(
			(location) => location.latitude !== null && location.longitude !== null
		) as Array<Props['locations'][0] & { latitude: number; longitude: number }>
	);

	onMount(() => {
		if (!mapContainer || !mapTilerKey) return;

		map = new maplibregl.Map({
			container: mapContainer,
			style: `https://api.maptiler.com/maps/basic/style.json?key=${mapTilerKey}`,
			center: located[0] ? [located[0].longitude, located[0].latitude] : [151.2093, -33.8688],
			zoom: 10
		});

		for (const location of located) {
			new maplibregl.Marker(createMarkerElement(location))
				.setLngLat([location.longitude, location.latitude])
				.setPopup(new maplibregl.Popup({ offset: 25 }).setDOMContent(createPopupElement(location)))
				.addTo(map);
		}

		// fitBounds throws on an empty bounds object.
		if (located.length > 0) {
			const bounds = new maplibregl.LngLatBounds();
			for (const location of located) {
				bounds.extend([location.longitude, location.latitude]);
			}
			map.fitBounds(bounds, { padding: 50, maxZoom: 14 });
		}

		return () => map?.remove();
	});

	function createMarkerElement(location: Props['locations'][0]): HTMLElement {
		const colors: { [key: string]: string } = {
			'Head Office': 'bg-blue-500',
			Branch: 'bg-green-500',
			'Service Centre': 'bg-purple-500'
		};

		const element = document.createElement('div');
		element.className = `w-8 h-8 rounded-full ${
			(location.location_type && colors[location.location_type]) || 'bg-gray-500'
		} border-2 border-white shadow-lg cursor-pointer`;
		return element;
	}

	/**
	 * Built with `textContent` rather than `setHTML`. These values come from the
	 * database, so interpolating them into markup let a stored `<img onerror=...>`
	 * execute in the session of every user who opened the popup.
	 */
	function createPopupElement(location: Props['locations'][0]): HTMLElement {
		const wrapper = document.createElement('div');

		const name = document.createElement('h3');
		name.className = 'font-medium';
		name.textContent = location.name;

		const type = document.createElement('p');
		type.className = 'text-sm';
		type.textContent = location.location_type ?? '';

		const address = document.createElement('p');
		address.className = 'text-sm text-gray-600';
		address.textContent = location.address ?? '';

		wrapper.append(name, type, address);
		return wrapper;
	}
</script>

{#if !mapTilerKey}
	<div class="flex h-[400px] w-full items-center justify-center rounded-lg bg-gray-100">
		<p class="text-gray-500">Set PUBLIC_MAPTILER_KEY to display the map.</p>
	</div>
{:else if located.length === 0}
	<div class="flex h-[400px] w-full items-center justify-center rounded-lg bg-gray-100">
		<p class="text-gray-500">No locations have coordinates yet.</p>
	</div>
{:else}
	<div bind:this={mapContainer} class="h-[400px] w-full overflow-hidden rounded-lg shadow-md"></div>
{/if}

<style>
	:global(.maplibregl-popup) {
		max-width: 300px !important;
	}

	:global(.maplibregl-popup-content) {
		padding: 1rem !important;
	}
</style>
