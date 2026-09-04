/src/routes/organisations/+page.server.ts
```ts
import { supabase } from '$lib/services/supabase'
import type { PageServerLoad, Actions } from './$types'

export const load: PageServerLoad = async ({ url }) => {
    const searchParams = url.searchParams
    const page = parseInt(searchParams.get('page') || '1')
    const limit = 10
    const offset = (page - 1) * limit

    const { data: organisations, count } = await supabase
        .from('organisations')
        .select(`
            *,
            legal_details (
                entity_type,
                abn
            ),
            contact_info (
                phone,
                email
            )
        `, { count: 'exact' })
        .range(offset, offset + limit - 1)
        .order('legal_name')

    return {
        organisations,
        totalCount: count || 0,
        currentPage: page,
        totalPages: Math.ceil((count || 0) / limit)
    }
}

export const actions: Actions = {
    createOrganisation: async ({ request }) => {
        const formData = await request.formData()
        const { legalName, tradingName, dateEstablished } = Object.fromEntries(formData)

        const { data, error } = await supabase
            .from('organisations')
            .insert({
                legal_name: legalName,
                trading_name: tradingName,
                date_established: dateEstablished
            })
            .select()

        return { success: !error, data, error }
    }
}
```

/src/routes/organisations/+page.svelte
```svelte
<script lang="ts">
    import { enhance } from '$app/forms'
    import OrganisationTable from '$lib/components/tables/OrganisationTable.svelte'
    import Pagination from '$lib/components/common/Pagination.svelte'
    import { Button } from '$lib/components/common'
    
    let { data } = $props();

    let { organisations, totalCount, currentPage, totalPages } = $derived(data)
    let showCreateForm = $state(false)
</script>

<div class="container mx-auto px-4 py-8">
    <div class="flex justify-between items-center mb-6">
        <div>
            <h1 class="text-2xl font-bold">Organisations</h1>
            <p class="text-gray-600">Total: {totalCount}</p>
        </div>
        <Button on:click={() => showCreateForm = true}>
            Add Organisation
        </Button>
    </div>

    <OrganisationTable {organisations} />
    
    <div class="mt-4">
        <Pagination 
            {currentPage} 
            {totalPages} 
            baseUrl="/organisations" 
        />
    </div>
</div>
```

/src/routes/organisations/[id]/+page.server.ts
```ts
import { supabase } from '$lib/services/supabase'
import type { PageServerLoad, Actions } from './$types'

export const load: PageServerLoad = async ({ params }) => {
    const [organisation, relationships] = await Promise.all([
        supabase
            .from('organisations')
            .select(`
                *,
                legal_details (*),
                contact_info (*),
                operational_details (*),
                financial_info (*),
                governance (*),
                programs_services (*),
                accreditation (*),
                resources_assets (*)
            `)
            .eq('org_id', params.id)
            .single(),
        supabase
            .from('relationships')
            .select('*')
            .eq('org_id', params.id)
    ])

    return { 
        organisation: organisation.data,
        relationships: relationships.data
    }
}

export const actions: Actions = {
    updateOrganisation: async ({ request }) => {
        const formData = await request.formData()
        const { orgId, ...updateData } = Object.fromEntries(formData)

        const { data, error } = await supabase
            .from('organisations')
            .update(updateData)
            .eq('org_id', orgId)
            .select()

        return { success: !error, data, error }
    }
}
```

/src/routes/organisations/[id]/+page.svelte
```svelte
<script lang="ts">
    import { enhance } from '$app/forms'
    import { Button, Card } from '$lib/components/common'
    import OrganisationDetails from '$lib/components/organisations/OrganisationDetails.svelte'
    import RelationshipsTable from '$lib/components/tables/RelationshipsTable.svelte'
    
    let { data } = $props();

    let { organisation, relationships } = $derived(data)
    let isEditing = $state(false)
</script>

<div class="container mx-auto px-4 py-8">
    <div class="flex justify-between items-center mb-6">
        <div>
            <h1 class="text-2xl font-bold">{organisation.legal_name}</h1>
            {#if organisation.trading_name}
                <p class="text-gray-600">Trading as: {organisation.trading_name}</p>
            {/if}
        </div>
        <div class="flex gap-4">
            <Button 
                href="/organisations/{organisation.org_id}/roles"
                variant="secondary"
            >
                Manage Roles
            </Button>
            <Button on:click={() => isEditing = !isEditing}>
                {isEditing ? 'Cancel Edit' : 'Edit Details'}
            </Button>
        </div>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div class="lg:col-span-2">
            <OrganisationDetails 
                {organisation} 
                {isEditing} 
            />
        </div>
        
        <div>
            <Card title="Relationships">
                <RelationshipsTable {relationships} />
                <div class="mt-4">
                    <Button 
                        href="/organisations/{organisation.org_id}/relationships/new"
                        variant="secondary"
                        class="w-full"
                    >
                        Add Relationship
                    </Button>
                </div>
            </Card>
        </div>
    </div>
</div>
```
OrganisationTable.svelte
```svelte
<script lang="ts">
    interface Props {
        organisations: Array<{
        org_id: number;
        legal_name: string;
        trading_name: string | null;
        date_established: string;
        legal_details: {
            entity_type: string;
            abn: string;
        };
        contact_info: {
            phone: string;
            email: string;
        };
    }>;
    }

    let { organisations }: Props = $props();
</script>

<div class="overflow-x-auto">
    <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
            <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Organisation
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Entity Type
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Contact
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                </th>
            </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
            {#each organisations as org}
                <tr>
                    <td class="px-6 py-4">
                        <div>
                            <div class="font-medium">{org.legal_name}</div>
                            {#if org.trading_name}
                                <div class="text-sm text-gray-500">{org.trading_name}</div>
                            {/if}
                        </div>
                    </td>
                    <td class="px-6 py-4">
                        <div>
                            <div>{org.legal_details.entity_type}</div>
                            <div class="text-sm text-gray-500">ABN: {org.legal_details.abn}</div>
                        </div>
                    </td>
                    <td class="px-6 py-4">
                        <div>
                            <div>{org.contact_info.email}</div>
                            <div class="text-sm text-gray-500">{org.contact_info.phone}</div>
                        </div>
                    </td>
                    <td class="px-6 py-4">
                        <a 
                            href="/organisations/{org.org_id}" 
                            class="text-indigo-600 hover:text-indigo-900"
                        >
                            View Details
                        </a>
                    </td>
                </tr>
            {/each}
        </tbody>
    </table>
</div>
```

Pagination.svelte
```svelte
<script lang="ts">
    interface Props {
        currentPage: number;
        totalPages: number;
        baseUrl: string;
    }

    let { currentPage, totalPages, baseUrl }: Props = $props();

    let pages = $derived(Array.from({ length: totalPages }, (_, i) => i + 1));
    let visiblePages = $derived(pages.filter(page => 
        page === 1 || 
        page === totalPages || 
        (page >= currentPage - 1 && page <= currentPage + 1)
    ));
</script>

<nav class="flex justify-center space-x-2">
    {#each visiblePages as page}
        {#if page === visiblePages[0] && page > 1}
            <span class="px-3 py-2">...</span>
        {/if}
        
        <a
            href="{baseUrl}?page={page}"
            class="px-3 py-2 rounded-md {page === currentPage 
                ? 'bg-indigo-600 text-white' 
                : 'text-gray-700 hover:bg-gray-50'}"
        >
            {page}
        </a>

        {#if page === visiblePages[visiblePages.length - 1] && page < totalPages}
            <span class="px-3 py-2">...</span>
        {/if}
    {/each}
</nav>
```

OrganisationDetails.svelte 
```svelte
<script lang="ts">
    import { enhance } from '$app/forms'
    import { Card, Button } from '$lib/components/common'

    interface Props {
        organisation: {
        org_id: number;
        legal_name: string;
        trading_name: string | null;
        date_established: string;
        legal_details: any;
        contact_info: any;
        operational_details: any;
        financial_info: any;
    };
        isEditing?: boolean;
    }

    let { organisation, isEditing = false }: Props = $props();

    let formData = $state({ ...organisation });
</script>

<div class="space-y-6">
    {#if isEditing}
        <form 
            method="POST" 
            action="?/updateOrganisation"
            use:enhance
            class="space-y-6"
        >
            <input type="hidden" name="orgId" value={organisation.org_id}>
            
            <Card title="Basic Information">
                <div class="space-y-4">
                    <div>
                        <label>Legal Name</label>
                        <input 
                            type="text" 
                            name="legal_name"
                            bind:value={formData.legal_name}
                            class="input"
                        />
                    </div>
                    <div>
                        <label>Trading Name</label>
                        <input 
                            type="text" 
                            name="trading_name"
                            bind:value={formData.trading_name}
                            class="input"
                        />
                    </div>
                </div>
            </Card>

            <!-- Additional form sections for other details -->
            
            <div class="flex justify-end">
                <Button type="submit">Save Changes</Button>
            </div>
        </form>
    {:else}
        <Card title="Basic Information">
            <div class="space-y-2">
                <div>
                    <span class="font-medium">Legal Name:</span>
                    {organisation.legal_name}
                </div>
                {#if organisation.trading_name}
                    <div>
                        <span class="font-medium">Trading Name:</span>
                        {organisation.trading_name}
                    </div>
                {/if}
                <div>
                    <span class="font-medium">Established:</span>
                    {new Date(organisation.date_established).toLocaleDateString()}
                </div>
            </div>
        </Card>

        <!-- Additional display cards for other details -->
    {/if}
</div>
```

RelationshipsTable.svelte
```svelte
<script lang="ts">
    import { formatDate } from '$lib/utils/formatters'

    interface Props {
        relationships: Array<{
        relationship_id: number;
        partner_org: string;
        relationship_type: string;
        start_date: string;
        end_date: string | null;
    }>;
    }

    let { relationships }: Props = $props();
</script>

<div class="overflow-x-auto">
    <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
            <tr>
                <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                    Partner
                </th>
                <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                    Type
                </th>
                <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                    Duration
                </th>
            </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
            {#each relationships as relationship}
                <tr>
                    <td class="px-4 py-2">
                        <a 
                            href="/relationships/{relationship.relationship_id}"
                            class="text-indigo-600 hover:text-indigo-900"
                        >
                            {relationship.partner_org}
                        </a>
                    </td>
                    <td class="px-4 py-2">
                        {relationship.relationship_type}
                    </td>
                    <td class="px-4 py-2">
                        {formatDate(relationship.start_date)} - 
                        {relationship.end_date ? formatDate(relationship.end_date) : 'Present'}
                    </td>
                </tr>
            {/each}
        </tbody>
    </table>
</div>
```