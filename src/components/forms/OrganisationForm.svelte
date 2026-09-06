<script lang="ts">
	import { enhance } from '$app/forms';
	import type { Database } from '$lib/db.types';

	type Organisation = Database['community_orgs']['Tables']['organisations']['Row'];

	interface Props {
		/** Omitted when the form is creating a new organisation. */
		organisation?: Pick<
			Organisation,
			'entity_name' | 'description' | 'date_established' | 'is_public'
		> | null;
		/** The named form action to post to, e.g. `createOrganisation`. */
		action: string;
		errors?: Record<string, string[] | undefined>;
		onSave?: () => void;
	}

	let { organisation = null, action, errors, onSave }: Props = $props();
</script>

<form
	method="POST"
	action="?/{action}"
	use:enhance={() => {
		return ({ result, update }) => {
			if (result.type === 'success') onSave?.();
			return update();
		};
	}}
	class="space-y-6"
>
	<div class="grid grid-cols-1 gap-6 md:grid-cols-2">
		<div>
			<label class="label label-text" for="entity_name">Entity Name</label>
			<input
				type="text"
				id="entity_name"
				name="entity_name"
				value={organisation?.entity_name ?? ''}
				required
				class="input w-full"
			/>
			{#if errors?.entity_name}
				<p class="text-error-500 text-sm">{errors.entity_name[0]}</p>
			{/if}
			{#if !organisation}
				<p class="text-surface-600-400 text-sm">The URL slug is generated from this name.</p>
			{/if}
		</div>

		<div>
			<label class="label label-text" for="date_established">Date Established</label>
			<input
				type="date"
				id="date_established"
				name="date_established"
				value={organisation?.date_established ?? ''}
				class="input w-full"
			/>
		</div>

		<div class="md:col-span-2">
			<label class="label label-text" for="description">Description</label>
			<textarea id="description" name="description" rows="3" class="textarea w-full"
				>{organisation?.description ?? ''}</textarea
			>
		</div>

		<div class="flex items-center gap-2">
			<input
				class="checkbox"
				id="is_public"
				type="checkbox"
				name="is_public"
				checked={organisation?.is_public ?? true}
			/>
			<label class="label-text" for="is_public">Publicly visible</label>
		</div>
	</div>

	<div class="flex justify-end gap-4">
		<button type="submit" class="btn preset-filled">
			{organisation ? 'Update' : 'Create'} Organisation
		</button>
	</div>
</form>
