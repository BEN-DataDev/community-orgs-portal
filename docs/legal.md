# Path: /src/routes/organisations/[id]/legal/+page.server.ts

```ts
import { supabase } from '$lib/services/supabase';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ params }) => {
 const { data: legalInfo } = await supabase
  .from('legal_details')
  .select(
   `
            *,
            organizations (
                legal_name,
                trading_name
            )
        `
  )
  .eq('org_id', params.id)
  .single();

 return { legalInfo };
};

export const actions: Actions = {
 updateLegal: async ({ request }) => {
  const formData = await request.formData();
  const { orgId, ...legalData } = Object.fromEntries(formData);

  const { data, error } = await supabase
   .from('legal_details')
   .upsert({
    org_id: orgId,
    ...legalData
   })
   .select();

  return { success: !error, data };
 }
};
```

/src/routes/organisations/[id]/legal/+page.svelte

```svelte
<script lang="ts">
 import { enhance } from '$app/forms';
 import { Button, Card } from '$lib/components/common';
 import LegalForm from '$lib/components/forms/LegalForm.svelte';

 let { data } = $props();

 let { legalInfo } = $derived(data);
 let isEditing = $state(false);
</script>

<div class="container mx-auto px-4 py-8">
 <div class="mb-6 flex items-center justify-between">
  <div>
   <h1 class="text-2xl font-bold">Legal Information</h1>
   <p class="text-gray-600">{legalInfo.organizations.legal_name}</p>
  </div>
  <Button on:click={() => (isEditing = !isEditing)}>
   {isEditing ? 'Cancel' : 'Edit Legal Info'}
  </Button>
 </div>

 {#if isEditing}
  <LegalForm {legalInfo} on:save={() => (isEditing = false)} />
 {:else}
  <div class="grid grid-cols-1 gap-6 md:grid-cols-2">
   <Card title="Entity Details">
    <div class="space-y-2">
     <p><strong>Entity Type:</strong> {legalInfo.entity_type}</p>
     <p><strong>ABN:</strong> {legalInfo.abn}</p>
     <p><strong>ACN:</strong> {legalInfo.acn}</p>
     <p>
      <strong>Registration Date:</strong>
      {new Date(legalInfo.registration_date).toLocaleDateString()}
     </p>
    </div>
   </Card>

   <Card title="Compliance">
    <div class="space-y-2">
     <p><strong>Tax Status:</strong> {legalInfo.tax_status}</p>
     <p><strong>Charity Status:</strong> {legalInfo.charity_status}</p>
     <p>
      <strong>Last Annual Return:</strong>
      {new Date(legalInfo.last_annual_return_date).toLocaleDateString()}
     </p>
    </div>
   </Card>

   <Card title="Documents">
    <div class="space-y-2">
     {#each legalInfo.documents as doc}
      <div class="flex items-center justify-between">
       <span>{doc.name}</span>
       <a href={doc.url} class="text-indigo-600 hover:text-indigo-900"> Download </a>
      </div>
     {/each}
    </div>
   </Card>
  </div>
 {/if}
</div>
```

LegalForm.svelte

```svelte
<script lang="ts">
 import { enhance } from '$app/forms';
 import { Button } from '$lib/components/common';

 interface Props {
  legalInfo: any;
 }

 let { legalInfo }: Props = $props();

 let documents = $state(legalInfo.documents || []);

 function addDocument() {
  documents = [...documents, { name: '', url: '' }];
 }

 function removeDocument(index: number) {
  documents = documents.filter((_, i) => i !== index);
 }
</script>

<form method="POST" action="?/updateLegal" use:enhance class="space-y-6">
 <input type="hidden" name="orgId" value={legalInfo.org_id} />
 <input type="hidden" name="documents" value={JSON.stringify(documents)} />

 <div class="grid grid-cols-1 gap-6 md:grid-cols-2">
  <div>
   <label>Entity Type</label>
   <select name="entity_type" value={legalInfo.entity_type} required>
    <option value="Company">Company</option>
    <option value="Trust">Trust</option>
    <option value="Association">Association</option>
    <option value="Partnership">Partnership</option>
   </select>
  </div>

  <div>
   <label>ABN</label>
   <input type="text" name="abn" value={legalInfo.abn} required />
  </div>

  <div>
   <label>ACN</label>
   <input type="text" name="acn" value={legalInfo.acn} />
  </div>

  <div>
   <label>Registration Date</label>
   <input type="date" name="registration_date" value={legalInfo.registration_date} required />
  </div>

  <div>
   <label>Tax Status</label>
   <select name="tax_status" value={legalInfo.tax_status} required>
    <option value="For-Profit">For-Profit</option>
    <option value="Non-Profit">Non-Profit</option>
    <option value="Charity">Charity</option>
   </select>
  </div>

  <div>
   <label>Charity Status</label>
   <select name="charity_status" value={legalInfo.charity_status}>
    <option value="Registered">Registered</option>
    <option value="Not Registered">Not Registered</option>
   </select>
  </div>
 </div>

 <div>
  <h3 class="mb-2 font-medium">Legal Documents</h3>
  {#each documents as doc, index}
   <div class="mb-2 flex gap-4">
    <input type="text" bind:value={doc.name} placeholder="Document name" />
    <input type="url" bind:value={doc.url} placeholder="Document URL" />
    <Button type="button" variant="danger" on:click={() => removeDocument(index)}>
     Remove
    </Button>
   </div>
  {/each}
  <Button type="button" on:click={addDocument}>Add Document</Button>
 </div>

 <div class="flex justify-end">
  <Button type="submit">Save Changes</Button>
 </div>
</form>
```
