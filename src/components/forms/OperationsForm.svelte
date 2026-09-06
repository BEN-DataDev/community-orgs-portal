<script lang="ts">
	import { enhance } from '$app/forms';
	import type { Database } from '$lib/db.types';

	type OperationalDetails = Database['community_orgs']['Tables']['operational_details']['Row'];

	interface DayHours {
		day: string;
		open: string;
		close: string;
	}

	interface Props {
		operationalInfo: OperationalDetails | null;
		errors?: Record<string, string[] | undefined>;
		onSave?: () => void;
	}

	let { operationalInfo = null, errors, onSave }: Props = $props();

	const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

	/**
	 * `operating_hours` is a JSON column. It is read defensively because nothing
	 * constrains its shape at the database level.
	 */
	function readHours(value: OperationalDetails['operating_hours']): DayHours[] {
		const stored = Array.isArray(value) ? (value as unknown as Partial<DayHours>[]) : [];
		return DAYS.map((day) => {
			const match = stored.find((entry) => entry?.day === day);
			return { day, open: match?.open ?? '', close: match?.close ?? '' };
		});
	}

	let hours = $state<DayHours[]>([]);

	// Re-seeded whenever the saved record changes, e.g. after a successful save.
	$effect(() => {
		hours = readHours(operationalInfo?.operating_hours ?? null);
	});

	/** Only days with both times set are stored. */
	let hoursPayload = $derived(
		JSON.stringify(hours.filter((entry) => entry.open !== '' && entry.close !== ''))
	);
</script>

<form
	method="POST"
	action="?/updateOperations"
	use:enhance={() => {
		return ({ result, update }) => {
			if (result.type === 'success') onSave?.();
			return update();
		};
	}}
	class="space-y-6"
>
	<input class="input" type="hidden" name="operating_hours" value={hoursPayload} />

	<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
		<div>
			<label class="label label-text" for="staff_count_paid">Paid Staff</label>
			<input
				class="input"
				type="number"
				min="0"
				id="staff_count_paid"
				name="staff_count_paid"
				value={operationalInfo?.staff_count_paid ?? ''}
			/>
			{#if errors?.staff_count_paid}
				<p class="text-error-500 text-sm">{errors.staff_count_paid[0]}</p>
			{/if}
		</div>

		<div>
			<label class="label label-text" for="staff_count_volunteer">Volunteers</label>
			<input
				class="input"
				type="number"
				min="0"
				id="staff_count_volunteer"
				name="staff_count_volunteer"
				value={operationalInfo?.staff_count_volunteer ?? ''}
			/>
		</div>

		<div>
			<label class="label label-text" for="service_area">Service Area</label>
			<input
				class="input"
				type="text"
				id="service_area"
				name="service_area"
				value={operationalInfo?.service_area ?? ''}
			/>
		</div>

		<div>
			<label class="label label-text" for="target_demographics">Target Demographics</label>
			<input
				class="input"
				type="text"
				id="target_demographics"
				name="target_demographics"
				value={operationalInfo?.target_demographics ?? ''}
			/>
		</div>

		<div>
			<label class="label label-text" for="languages_supported">Languages Supported</label>
			<input
				class="input"
				type="text"
				id="languages_supported"
				name="languages_supported"
				placeholder="Comma-separated"
				value={(operationalInfo?.languages_supported ?? []).join(', ')}
			/>
		</div>

		<div>
			<label class="label label-text" for="accessibility_features">Accessibility Features</label>
			<input
				class="input"
				type="text"
				id="accessibility_features"
				name="accessibility_features"
				placeholder="Comma-separated"
				value={(operationalInfo?.accessibility_features ?? []).join(', ')}
			/>
		</div>
	</div>

	<fieldset>
		<legend class="mb-2 font-medium">Operating Hours</legend>
		{#each hours as entry (entry.day)}
			<div class="mb-2 flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-4">
				<span class="font-medium sm:w-28 sm:font-normal">{entry.day}</span>
				<input
					class="input"
					type="time"
					bind:value={entry.open}
					aria-label="{entry.day} opening time"
				/>
				<input
					class="input"
					type="time"
					bind:value={entry.close}
					aria-label="{entry.day} closing time"
				/>
			</div>
		{/each}
	</fieldset>

	<div class="flex justify-end">
		<button class="btn preset-filled" type="submit">Save Changes</button>
	</div>
</form>
