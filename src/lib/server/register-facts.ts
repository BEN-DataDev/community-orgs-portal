import { error } from '@sveltejs/kit';
import type { TypedSupabaseClient } from '$lib/supabase-client';
import { registerFactsSchema } from '$lib/register-facts';

export async function loadRegisterFacts(supabase: TypedSupabaseClient, orgId: string) {
	const result = await supabase.rpc('organisation_register_facts', { p_organisation: orgId });
	const parsed = registerFactsSchema.safeParse(result.data);
	if (result.error || !parsed.success) error(500, 'Could not load published register details.');
	return parsed.data;
}
