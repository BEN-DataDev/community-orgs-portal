<script lang="ts">
	import { enhance } from '$app/forms';

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
		onSave?: () => void;
	}

	let { operationalInfo, onSave }: Props = $props();

	function handleSubmit(event: SubmitEvent) {
		if (!validateForm()) {
			event.preventDefault();
			alert('Please fill in all required fields correctly');
			return;
		}
		onSave?.();
	}

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
	use:enhance={() => {
		return ({ result }: { result: { type: string } }) => {
			if (result.type === 'success') {
				onSave?.();
			}
		};
	}}
	onsubmit={handleSubmit}
	class="space-y-6"
>
	<input type="hidden" name="orgId" value={operationalInfo.org_id} />
	<input type="hidden" name="locations" value={JSON.stringify(locations)} />
	<input type="hidden" name="service_areas" value={JSON.stringify(serviceAreas)} />

	<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
		<div>
			<label for="staff_count" class="mb-2 block">Staff Count</label>
			<input
				type="number"
				id="staff_count"
				name="staff_count"
				min="0"
				value={operationalInfo.staff_count}
				required
				class="w-full"
			/>
		</div>

		<div>
			<label for="volunteer_count" class="mb-2 block">Volunteer Count</label>
			<input
				type="number"
				id="volunteer_count"
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
				<button
					type="button"
					class="preset-filled-warning btn btn-md"
					onclick={() => removeLocation(index)}
				>
					Remove
				</button>
			</div>
		{/each}
		<button type="button" class="btn btn-md preset-filled" onclick={addLocation}
			>Add Location</button
		>
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
		<button type="submit" class="btn btn-md preset-filled">Save Changes</button>
	</div>
</form>
