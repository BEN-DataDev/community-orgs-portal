import { error } from '@sveltejs/kit';
import type { TypedSupabaseClient } from '$lib/supabase-client';
import { EDITOR_LEVEL, ROLE_LEVEL } from '$lib/role-levels';

export { EDITOR_LEVEL, ROLE_LEVEL };

/**
 * These checks mirror the database's row-level security policies, which are the
 * actual boundary: every `community_orgs` table enforces the same rules through
 * `community_orgs.can_view_org` / `can_edit_org`, so a caller who bypasses this
 * application and talks to PostgREST directly gets the same answer.
 *
 * Checking here as well means the UI can hide controls the user cannot use, and
 * failures surface as a 403 page rather than an opaque database error.
 */

export async function orgRoleLevel(
	supabase: TypedSupabaseClient,
	userId: string | undefined,
	orgId: string
): Promise<number> {
	if (!userId) return 0;

	const { data, error: rpcError } = await supabase.rpc('user_max_role_level', {
		p_organisation_id: orgId,
		p_user_id: userId
	});

	if (rpcError) {
		console.error('Failed to resolve role level:', rpcError);
		return 0;
	}

	return data ?? 0;
}

export async function userOrganisations(supabase: TypedSupabaseClient, userId: string) {
	const { data, error: rpcError } = await supabase.rpc('get_user_organisations_with_roles', {
		p_user_id: userId
	});

	if (rpcError) {
		console.error('Failed to load user organisations:', rpcError);
		return [];
	}

	return data ?? [];
}

/**
 * Reading an organisation: allowed when it is marked public, or when the user
 * holds any active role on it.
 */
export async function requireOrgAccess(
	supabase: TypedSupabaseClient,
	userId: string | undefined,
	orgId: string,
	isPublic: boolean
): Promise<number> {
	const level = await orgRoleLevel(supabase, userId, orgId);
	if (isPublic || level >= ROLE_LEVEL.member) {
		return level;
	}
	error(403, 'You do not have access to this organisation.');
}

/** Changing an organisation's records requires admin or owner on it. */
export async function requireOrgEditor(
	supabase: TypedSupabaseClient,
	userId: string | undefined,
	orgId: string
): Promise<number> {
	const level = await orgRoleLevel(supabase, userId, orgId);
	if (level >= EDITOR_LEVEL) {
		return level;
	}
	error(403, 'You do not have permission to change this organisation.');
}

/**
 * `/admin` is a site-wide area, but the schema only models per-organisation
 * roles. The closest honest mapping is: an admin or owner of at least one
 * organisation.
 */
export async function isSiteAdmin(
	supabase: TypedSupabaseClient,
	userId: string | undefined
): Promise<boolean> {
	if (!userId) return false;
	const organisations = await userOrganisations(supabase, userId);
	return organisations.some((org) => (org.max_hierarchy_level ?? 0) >= EDITOR_LEVEL);
}
