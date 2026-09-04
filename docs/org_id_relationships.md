/src/routes/organisations/[id]/relationships/+page.server.ts
```ts
import { supabase } from '$lib/services/supabase'
import type { PageServerLoad, Actions } from './$types'

export const load: PageServerLoad = async ({ params }) => {
    const [relationships, organisation] = await Promise.all([
        supabase
            .from('relationships')
            .select(`
                *,
                partner_details:organisations!partner_org_id (
                    legal_name,
                    trading_name
                )
            `)
            .eq('org_id', params.id)
            .order('start_date', { ascending: false }),
        supabase
            .from('organisations')
            .select('legal_name, trading_name')
            .eq('org_id', params.id)
            .single()
    ])

    return { 
        relationships: relationships.data,
        organisation: organisation.data
    }
}

export const actions: Actions = {
    createRelationship: async ({ request }) => {
        const formData = await request.formData()
        const relationshipData = Object.fromEntries(formData)

        const { data, error } = await supabase
            .from('relationships')
            .insert(relationshipData)
            .select()

        return { success: !error, data }
    }
}
```

/src/routes/organisations/[id]/relationships/+page.svelte
```svelte
<script lang="ts">
    import { enhance } from '$app/forms'
    import { Button, Card } from '$lib/components/common'
    import RelationshipForm from '$lib/components/forms/RelationshipForm.svelte'
    import RelationshipTimeline from '$lib/components/visualizations/RelationshipTimeline.svelte'
    
    let { data } = $props();
    
    let { relationships, organisation } = $derived(data)
    let showCreateForm = $state(false)
</script>

<div class="container mx-auto px-4 py-8">
    <div class="flex justify-between items-center mb-6">
        <div>
            <h1 class="text-2xl font-bold">Relationships</h1>
            <p class="text-gray-600">{organisation.legal_name}</p>
        </div>
        <Button on:click={() => showCreateForm = !showCreateForm}>
            {showCreateForm ? 'Cancel' : 'Add Relationship'}
        </Button>
    </div>

    {#if showCreateForm}
        <Card>
            <RelationshipForm 
                orgId={organisation.org_id}
                on:save={() => showCreateForm = false}
            />
        </Card>
    {/if}

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 mt-6">
        <div class="lg:col-span-2">
            <RelationshipTimeline {relationships} />
        </div>

        <div>
            <Card title="Active Relationships">
                {#each relationships.filter(r => !r.end_date) as relationship}
                    <div class="p-4 border-b last:border-0">
                        <h3 class="font-medium">
                            {relationship.partner_details.legal_name}
                        </h3>
                        <p class="text-sm text-gray-600">
                            {relationship.relationship_type}
                        </p>
                        <p class="text-sm text-gray-500">
                            Since {new Date(relationship.start_date).toLocaleDateString()}
                        </p>
                    </div>
                {/each}
            </Card>
        </div>
    </div>
</div>
```

RelationshipForm.svelte
```svelte
<script lang="ts">
    import { enhance } from '$app/forms'
    import { Button } from '$lib/components/common'
    import OrganisationSearch from '$lib/components/common/OrganisationSearch.svelte'
    
    interface Props {
        orgId: number;
    }

    let { orgId }: Props = $props();
    
    let selectedPartner: any = $state(null)
    let relationshipType = $state('')
    let startDate = $state('')
    let endDate = $state('')
    let description = $state('')

    const relationshipTypes = [
        'Partnership',
        'Funding',
        'Service Provider',
        'Network Member',
        'Collaboration',
        'Strategic Alliance'
    ]
</script>

<form 
    method="POST" 
    action="?/createRelationship"
    use:enhance
    class="space-y-6"
>
    <input type="hidden" name="org_id" value={orgId}>
    <input type="hidden" name="partner_org_id" value={selectedPartner?.org_id}>
    
    <div>
        <label>Partner Organisation</label>
        <OrganisationSearch bind:selected={selectedPartner} />
    </div>
    
    <div>
        <label>Relationship Type</label>
        <select 
            bind:value={relationshipType}
            name="relationship_type"
            required
            class="w-full"
        >
            <option value="">Select type...</option>
            {#each relationshipTypes as type}
                <option value={type}>{type}</option>
            {/each}
        </select>
    </div>
    
    <div class="grid grid-cols-2 gap-4">
        <div>
            <label>Start Date</label>
            <input 
                type="date" 
                bind:value={startDate}
                name="start_date"
                required
            >
        </div>
        <div>
            <label>End Date</label>
            <input 
                type="date" 
                bind:value={endDate}
                name="end_date"
            >
        </div>
    </div>
    
    <div>
        <label>Description</label>
        <textarea 
            bind:value={description}
            name="description"
            rows="3"
            class="w-full"
        ></textarea>
    </div>

    <div class="flex justify-end gap-4">
        <Button type="submit" disabled={!selectedPartner}>
            Create Relationship
        </Button>
    </div>
</form>
```

OrganisationSearch.svelte
```svelte
<script lang="ts">
    import { createEventDispatcher } from 'svelte'
    import { debounce } from '$lib/utils/debounce'
    import { supabase } from '$lib/services/supabase'
    
    interface Props {
        selected?: any;
        placeholder?: string;
        excludeIds?: number[];
    }

    let { selected = $bindable(null), placeholder = 'Search organisations...', excludeIds = [] }: Props = $props();
    
    const dispatch = createEventDispatcher()
    
    let searchTerm = $state('')
    let results: any[] = $state([])
    let isLoading = $state(false)
    let showResults = $state(false)
    
    const searchOrganisations = debounce(async (term: string) => {
        if (term.length < 2) {
            results = []
            return
        }
        
        isLoading = true
        
        const { data, error } = await supabase
            .from('organisations')
            .select('org_id, legal_name, trading_name')
            .ilike('legal_name', `%${term}%`)
            .not('org_id', 'in', `(${excludeIds.join(',')})`)
            .limit(10)
        
        isLoading = false
        
        if (!error && data) {
            results = data
        }
    }, 300)
    
    function handleSelect(org: any) {
        selected = org
        searchTerm = org.legal_name
        showResults = false
        dispatch('select', org)
    }
    
    function handleFocus() {
        if (searchTerm.length >= 2) {
            showResults = true
        }
    }
    
    function handleBlur() {
        setTimeout(() => {
            showResults = false
        }, 200)
    }
</script>

<div class="relative">
    <input
        type="text"
        bind:value={searchTerm}
        oninput={() => {
            searchOrganisations(searchTerm)
            showResults = true
        }}
        onfocus={handleFocus}
        onblur={handleBlur}
        {placeholder}
        class="w-full px-4 py-2 border rounded-md"
    />
    
    {#if isLoading}
        <div class="absolute right-3 top-2.5">
            <div class="animate-spin h-5 w-5 border-2 border-indigo-500 rounded-full border-t-transparent"></div>
        </div>
    {/if}
    
    {#if showResults && results.length > 0}
        <div class="absolute z-50 w-full mt-1 bg-white border rounded-md shadow-lg max-h-60 overflow-auto">
            {#each results as org}
                <button
                    type="button"
                    class="w-full px-4 py-2 text-left hover:bg-gray-100 focus:bg-gray-100 focus:outline-none"
                    onclick={() => handleSelect(org)}
                >
                    <div>{org.legal_name}</div>
                    {#if org.trading_name}
                        <div class="text-sm text-gray-600">
                            Trading as: {org.trading_name}
                        </div>
                    {/if}
                </button>
            {/each}
        </div>
    {/if}
</div>
```


RelationshipTimeline.svelte
```svelte
<script lang="ts">
    import { onMount } from 'svelte'
    import * as d3 from 'd3'
    
    interface Props {
        relationships: Array<{
        start_date: string;
        end_date: string | null;
        relationship_type: string;
        partner_details: {
            legal_name: string;
        };
    }>;
    }

    let { relationships }: Props = $props();

    let container: HTMLDivElement = $state()
    
    onMount(() => {
        const margin = { top: 20, right: 20, bottom: 30, left: 200 }
        const width = container.clientWidth - margin.left - margin.right
        const height = relationships.length * 40

        const svg = d3.select(container)
            .append('svg')
            .attr('width', width + margin.left + margin.right)
            .attr('height', height + margin.top + margin.bottom)
            .append('g')
            .attr('transform', `translate(${margin.left},${margin.top})`)

        const timeExtent = d3.extent([
            ...relationships.map(d => new Date(d.start_date)),
            ...relationships.map(d => d.end_date ? new Date(d.end_date) : new Date())
        ])

        const xScale = d3.scaleTime()
            .domain(timeExtent)
            .range([0, width])

        const yScale = d3.scaleBand()
            .domain(relationships.map(d => d.partner_details.legal_name))
            .range([0, height])
            .padding(0.1)

        // Draw axes
        svg.append('g')
            .attr('transform', `translate(0,${height})`)
            .call(d3.axisBottom(xScale))

        svg.append('g')
            .call(d3.axisLeft(yScale))

        // Draw relationship bars
        svg.selectAll('rect')
            .data(relationships)
            .enter()
            .append('rect')
            .attr('y', d => yScale(d.partner_details.legal_name))
            .attr('x', d => xScale(new Date(d.start_date)))
            .attr('width', d => {
                const end = d.end_date ? new Date(d.end_date) : new Date()
                return xScale(end) - xScale(new Date(d.start_date))
            })
            .attr('height', yScale.bandwidth())
            .attr('fill', d => getRelationshipColor(d.relationship_type))
            .append('title')
            .text(d => `${d.relationship_type}\n${d.partner_details.legal_name}`)
    })

    function getRelationshipColor(type: string): string {
        const colors = {
            'Partnership': '#4C51BF',
            'Funding': '#38A169',
            'Service Provider': '#ED8936',
            'Network Member': '#667EEA',
            'Collaboration': '#9F7AEA',
            'Strategic Alliance': '#ED64A6'
        }
        return colors[type] || '#718096'
    }
</script>

<div 
    bind:this={container}
    class="w-full h-full min-h-[400px]"
>
</div>

<style>
    :global(svg) {
        max-width: 100%;
        height: auto;
    }
</style>
```
