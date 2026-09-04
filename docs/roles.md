Here's the complete code for the role management route which fits under /organizations/[id]/roles/ in our app structure:

src/routes/organizations/[id]/roles/+page.server.ts

```ts
import { supabase } from '$lib/services/supabase';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ params }) => {
	const [roles, organization] = await Promise.all([
		supabase
			.from('role_definitions')
			.select(
				`
                *,
                created_by (
                    name,
                    email
                )
            `
			)
			.eq('org_id', params.id)
			.order('role_name'),
		supabase.from('organizations').select('org_id, legal_name').eq('org_id', params.id).single()
	]);

	return {
		roles: roles.data,
		organization: organization.data
	};
};

export const actions: Actions = {
	createRole: async ({ request }) => {
		const formData = await request.formData();
		const { roleName, description, permissions, orgId } = Object.fromEntries(formData);

		const { data, error } = await supabase
			.from('role_definitions')
			.insert({
				org_id: orgId,
				role_name: roleName,
				description,
				permissions: JSON.parse(permissions)
			})
			.select();

		return { success: !error, data, error };
	},

	deleteRole: async ({ request }) => {
		const formData = await request.formData();
		const roleId = formData.get('roleId');

		const { error } = await supabase.from('role_definitions').delete().eq('role_id', roleId);

		return { success: !error };
	}
};
```

src/routes/organizations/[id]/roles/+page.svelte

```svelte
<script lang="ts">
	import { enhance } from '$app/forms';
	import RoleBuilder from '$lib/components/forms/RoleBuilder.svelte';
	import { Button, Card } from '$lib/components/common';

	let { data } = $props();

	let { roles, organization } = $derived(data);
	let showBuilder = $state(false);

	function handleRoleCreated() {
		showBuilder = false;
	}
</script>

<div class="container mx-auto px-4 py-8">
	<div class="mb-6 flex items-center justify-between">
		<div>
			<h1 class="text-2xl font-bold">Role Management</h1>
			<p class="text-gray-600">{organization.legal_name}</p>
		</div>
		<Button on:click={() => (showBuilder = true)}>Create New Role</Button>
	</div>

	{#if showBuilder}
		<div class="mb-8">
			<RoleBuilder
				orgId={organization.org_id}
				on:created={handleRoleCreated}
				on:cancel={() => (showBuilder = false)}
			/>
		</div>
	{/if}

	<div class="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
		{#each roles as role}
			<Card>
				<div class="flex items-start justify-between">
					<div>
						<h3 class="text-lg font-semibold">{role.role_name}</h3>
						<p class="text-sm text-gray-600">{role.description}</p>
					</div>
					<form method="POST" action="?/deleteRole" use:enhance>
						<input type="hidden" name="roleId" value={role.role_id} />
						<Button variant="danger" size="sm">Delete</Button>
					</form>
				</div>
				<div class="mt-4">
					<h4 class="mb-2 font-medium">Permissions:</h4>
					<ul class="space-y-1 text-sm">
						{#each Object.entries(role.permissions) as [resource, perms]}
							<li>
								<span class="capitalize">{resource}:</span>
								{Object.entries(perms)
									.filter(([_, value]) => value)
									.map(([action]) => action)
									.join(', ')}
							</li>
						{/each}
					</ul>
				</div>
			</Card>
		{/each}
	</div>
</div>
```

RoleBuilder.svelte

```svelte
<script lang="ts">
	import { createEventDispatcher } from 'svelte';
	import { enhance } from '$app/forms';
	import { Button, Card } from '$lib/components/common';

	interface Props {
		orgId: number;
	}

	let { orgId }: Props = $props();

	const dispatch = createEventDispatcher();

	const permissionTypes = [
		'organizations',
		'relationships',
		'financial',
		'programs',
		'contacts',
		'assets'
	];

	const actions = ['read', 'write', 'delete'];

	let permissions = $state({});
	let roleName = $state('');
	let description = $state('');

	let permissionsJson = $derived(JSON.stringify(permissions));

	function initializePermissions() {
		permissionTypes.forEach((type) => {
			permissions[type] = {
				read: false,
				write: false,
				delete: false
			};
		});
	}

	function handleSubmitSuccess() {
		dispatch('created');
	}

	initializePermissions();
</script>

<Card>
	<form
		method="POST"
		action="?/createRole"
		use:enhance={() => {
			return ({ result }) => {
				if (result.type === 'success') {
					handleSubmitSuccess();
				}
			};
		}}
		class="space-y-6"
	>
		<div>
			<label class="block text-sm font-medium text-gray-700"> Role Name </label>
			<input
				type="text"
				bind:value={roleName}
				name="roleName"
				class="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
				required
			/>
		</div>

		<div>
			<label class="block text-sm font-medium text-gray-700"> Description </label>
			<textarea
				bind:value={description}
				name="description"
				class="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
				rows="3"
			></textarea>
		</div>

		<div>
			<h3 class="mb-4 text-sm font-medium text-gray-700">Permissions</h3>
			<div class="space-y-4">
				{#each permissionTypes as type}
					<div class="rounded-md border p-4">
						<h4 class="mb-2 font-medium capitalize">{type}</h4>
						<div class="flex gap-6">
							{#each actions as action}
								<label class="flex items-center">
									<input
										type="checkbox"
										bind:checked={permissions[type][action]}
										class="rounded border-gray-300"
									/>
									<span class="ml-2 text-sm capitalize">
										{action}
									</span>
								</label>
							{/each}
						</div>
					</div>
				{/each}
			</div>
		</div>

		<input type="hidden" name="permissions" value={permissionsJson} />
		<input type="hidden" name="orgId" value={orgId} />

		<div class="flex justify-end gap-4">
			<Button type="button" variant="secondary" on:click={() => dispatch('cancel')}>Cancel</Button>
			<Button type="submit">Create Role</Button>
		</div>
	</form>
</Card>
```
