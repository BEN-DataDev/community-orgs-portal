/src/routes/organisations/[id]/history/+page.server.ts
```ts
import { supabase } from '$lib/services/supabase'
import type { PageServerLoad, Actions } from './$types'

export const load: PageServerLoad = async ({ params }) => {
    const [historicalInfo, organisation] = await Promise.all([
        supabase
            .from('historical_info')
            .select(`
                *,
                inserted_by:auth.users!inserted_by(name, email),
                last_edited_by:auth.users!last_edited_by(name, email)
            `)
            .eq('org_id', params.id)
            .order('milestone_date', { ascending: false }),
        supabase
            .from('organisations')
            .select('legal_name, trading_name')
            .eq('org_id', params.id)
            .single()
    ])

    return { 
        historicalInfo: historicalInfo.data,
        organisation: organisation.data
    }
}

export const actions: Actions = {
    updateHistory: async ({ request }) => {
        const formData = await request.formData()
        const { orgId, foundingMembers, milestoneDate, milestoneDescription, structuralChanges } = Object.fromEntries(formData)

        const { data, error } = await supabase
            .from('historical_info')
            .upsert({
                org_id: orgId,
                founding_members: foundingMembers.split(',').map(m => m.trim()),
                milestone_date: milestoneDate,
                milestone_description: milestoneDescription,
                structural_changes: JSON.parse(structuralChanges),
                last_edited_at: new Date().toISOString()
            })
            .select()

        return { success: !error, data }
    }
}
```

/src/routes/organisations/[id]/history/+page.svelte
```svelte
<script lang="ts">
    import { Button, Card } from '$lib/components/common'
    import { formatDate } from '$lib/utils/formatters'
    
    let { data } = $props();
    
    let { historicalInfo, organisation } = $derived(data)
    let isEditing = $state(false)
</script>

<div class="container mx-auto px-4 py-8">
    <div class="flex justify-between items-center mb-6">
        <div>
            <h1 class="text-2xl font-bold">Historical Information</h1>
            <p class="text-gray-600">{organisation.legal_name}</p>
        </div>
        <Button on:click={() => isEditing = !isEditing}>
            {isEditing ? 'Cancel' : 'Add Historical Entry'}
        </Button>
    </div>

    {#if isEditing}
        <Card>
            <form method="POST" action="?/updateHistory" class="space-y-6">
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div>
                        <label>Founding Members</label>
                        <input type="text" name="foundingMembers" placeholder="Comma-separated names">
                    </div>
                    
                    <div>
                        <label>Milestone Date</label>
                        <input type="date" name="milestoneDate" required>
                    </div>
                    
                    <div class="md:col-span-2">
                        <label>Milestone Description</label>
                        <textarea name="milestoneDescription" rows="3" required></textarea>
                    </div>
                    
                    <div class="md:col-span-2">
                        <label>Structural Changes</label>
                        <textarea 
                            name="structuralChanges" 
                            rows="3"
                            placeholder="Enter JSON format structural changes"
                        ></textarea>
                    </div>
                </div>

                <div class="flex justify-end">
                    <Button type="submit">Save Historical Entry</Button>
                </div>
            </form>
        </Card>
    {/if}

    <div class="mt-6 space-y-6">
        {#each historicalInfo as entry}
            <Card>
                <div class="space-y-4">
                    <div class="flex justify-between items-start">
                        <div>
                            <h3 class="font-medium">{formatDate(entry.milestone_date)}</h3>
                            <p class="text-gray-600">{entry.milestone_description}</p>
                        </div>
                    </div>

                    {#if entry.founding_members?.length}
                        <div>
                            <h4 class="font-medium mb-2">Founding Members</h4>
                            <div class="flex flex-wrap gap-2">
                                {#each entry.founding_members as member}
                                    <span class="px-3 py-1 bg-gray-100 rounded-full text-sm">
                                        {member}
                                    </span>
                                {/each}
                            </div>
                        </div>
                    {/if}

                    {#if entry.structural_changes}
                        <div>
                            <h4 class="font-medium mb-2">Structural Changes</h4>
                            <pre class="bg-gray-50 p-3 rounded text-sm">
                                {JSON.stringify(entry.structural_changes, null, 2)}
                            </pre>
                        </div>
                    {/if}

                    <div class="text-sm text-gray-500">
                        Last edited by {entry.last_edited_by.name} on {formatDate(entry.last_edited_at)}
                    </div>
                </div>
            </Card>
        {/each}
    </div>
</div>
```
