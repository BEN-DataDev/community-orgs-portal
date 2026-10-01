import { error } from '@sveltejs/kit';
import type { DomainDatabase } from '$lib/server/providers/contracts';
import { registerFactsSchema } from '$lib/register-facts';

export async function loadRegisterFacts(supabase: DomainDatabase, orgId: string) {
	const result = await supabase.rpc('organisation_register_facts', { p_organisation: orgId });
	const parsed = registerFactsSchema.safeParse(result.data);
	if (result.error || !parsed.success) error(500, 'Could not load published register details.');
	return parsed.data;
}

/**
 * Legal columns supplied by a public register record the organisation holds. The
 * database rejects portal edits to them; callers use this to show them read-only
 * and to leave them out of saves.
 */
export async function loadRegisterSourcedLegalFields(supabase: DomainDatabase, orgId: string) {
	const result = await supabase.rpc('register_sourced_legal_fields', { p_organisation: orgId });
	if (result.error) error(500, 'Could not load which legal details come from a register.');
	return result.data ?? [];
}
