<script lang="ts">
	import OperationsForm from '$components/forms/OperationsForm.svelte';
	import OperationsMap from '$components/maps/OperationsMap.svelte';
	import { EDITOR_LEVEL } from '$lib/role-levels';

	let { data, form } = $props();
	let { operationalInfo, locations, organisation, roleLevel } = $derived(data);
	let canEdit = $derived(roleLevel >= EDITOR_LEVEL);
	let isEditing = $state(false);

	/** `operating_hours` is a free-form JSON column; read it defensively. */
	let hours = $derived(
		Array.isArray(operationalInfo?.operating_hours)
			? (operationalInfo.operating_hours as unknown as Array<{
					day?: string;
					open?: string;
					close?: string;
				}>)
			: []
	);
</script>

<div>
	<div class="mb-6 flex items-center justify-between">
		<div>
			<h1 class="text-2xl font-bold">Operational Information</h1>
			<p class="text-gray-600">{organisation.entity_name}</p>
		</div>
		{#if canEdit}
			<button class="btn preset-filled" onclick={() => (isEditing = !isEditing)}>
				{isEditing ? 'Cancel' : 'Edit Operations'}
			</button>
		{/if}
	</div>

	{#if form?.message}
		<p class="mb-4 text-red-600">{form.message}</p>
	{/if}

	{#if isEditing && canEdit}
		<OperationsForm {operationalInfo} errors={form?.errors} onSave={() => (isEditing = false)} />
	{:else}
		<div class="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
			<div class="space-y-2 rounded-lg border p-4">
				<h2 class="font-medium">Staff &amp; Volunteers</h2>
				<p><strong>Paid staff:</strong> {operationalInfo?.staff_count_paid ?? '—'}</p>
				<p><strong>Volunteers:</strong> {operationalInfo?.staff_count_volunteer ?? '—'}</p>
			</div>

			<div class="space-y-2 rounded-lg border p-4">
				<h2 class="font-medium">Operating Hours</h2>
				{#each hours as entry}
					<div class="flex justify-between py-1">
						<span class="font-medium">{entry.day ?? '—'}</span>
						<span>{entry.open ?? '—'} – {entry.close ?? '—'}</span>
					</div>
				{:else}
					<p class="text-gray-600">Not recorded.</p>
				{/each}
			</div>

			<div class="space-y-2 rounded-lg border p-4">
				<h2 class="font-medium">Reach</h2>
				<p><strong>Service area:</strong> {operationalInfo?.service_area ?? '—'}</p>
				<p><strong>Target demographics:</strong> {operationalInfo?.target_demographics ?? '—'}</p>
				<p>
					<strong>Languages:</strong>
					{(operationalInfo?.languages_supported ?? []).join(', ') || '—'}
				</p>
				<p>
					<strong>Accessibility:</strong>
					{(operationalInfo?.accessibility_features ?? []).join(', ') || '—'}
				</p>
			</div>
		</div>

		<div class="mt-6 rounded-lg border p-4">
			<h2 class="mb-3 font-medium">Locations</h2>
			<div class="grid grid-cols-1 gap-4 md:grid-cols-2">
				<div class="space-y-3">
					{#each locations as location (location.location_id)}
						<div class="rounded-lg border p-3">
							<div class="flex items-start justify-between gap-3">
								<div>
									<h3 class="font-medium">{location.name}</h3>
									{#if location.address}
										<p class="text-sm text-gray-600">{location.address}</p>
									{/if}
									{#if location.location_type}
										<p class="text-sm text-gray-500">{location.location_type}</p>
									{/if}
									{#if location.latitude === null || location.longitude === null}
										<p class="text-sm text-gray-500">No coordinates — not shown on the map</p>
									{/if}
								</div>
								{#if canEdit}
									<form method="POST" action="?/deleteLocation">
										<input type="hidden" name="location_id" value={location.location_id} />
										<button type="submit" class="text-sm text-red-600 hover:underline">
											Remove
										</button>
									</form>
								{/if}
							</div>
						</div>
					{:else}
						<p class="text-gray-600">No locations recorded.</p>
					{/each}

					{#if canEdit}
						<form method="POST" action="?/addLocation" class="space-y-2 rounded-lg border p-3">
							<div>
								<label for="location_name">Name</label>
								<input id="location_name" name="name" type="text" required />
							</div>
							<div>
								<label for="location_address">Address</label>
								<input id="location_address" name="address" type="text" />
							</div>
							<div>
								<label for="location_type">Type</label>
								<select id="location_type" name="location_type">
									<option value="">Not recorded</option>
									<option value="Head Office">Head Office</option>
									<option value="Branch">Branch</option>
									<option value="Service Centre">Service Centre</option>
								</select>
							</div>
							<div class="grid grid-cols-2 gap-2">
								<div>
									<label for="latitude">Latitude</label>
									<input id="latitude" name="latitude" type="text" inputmode="decimal" />
								</div>
								<div>
									<label for="longitude">Longitude</label>
									<input id="longitude" name="longitude" type="text" inputmode="decimal" />
								</div>
							</div>
							<button type="submit" class="btn preset-filled">Add Location</button>
						</form>
					{/if}
				</div>

				<OperationsMap {locations} />
			</div>
		</div>
	{/if}
</div>
