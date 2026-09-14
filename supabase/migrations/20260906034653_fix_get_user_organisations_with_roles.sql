-- Recovered from the existing remote migration history to keep local replay aligned.
create or replace function community_orgs.get_user_organisations_with_roles(p_user_id uuid)
returns table(organisation_id uuid, organisation_name text, organisation_slug text, role_names text[], permissions jsonb, max_hierarchy_level integer)
language plpgsql
security definer
set search_path = ''
as $function$
BEGIN
    RETURN QUERY
    SELECT
        o.org_id,
        o.entity_name,
        o.slug,
        ARRAY_AGG(r.name) as role_names,
        JSONB_OBJECT_AGG(r.name, r.permissions) as permissions,
        MAX(r.hierarchy_level) as max_hierarchy_level
    FROM community_orgs.organisations o
    JOIN community_orgs.user_organisation_roles uor ON o.org_id = uor.organisation_id
    JOIN community_orgs.roles r ON uor.role_id = r.id
    WHERE uor.user_id = p_user_id
    AND uor.is_active = true
    AND (uor.expires_at IS NULL OR uor.expires_at > NOW())
    GROUP BY o.org_id, o.entity_name, o.slug
    ORDER BY o.entity_name;
END;
$function$;

revoke execute on function community_orgs.get_user_organisations_with_roles(uuid) from public, anon;
grant execute on function community_orgs.get_user_organisations_with_roles(uuid) to authenticated, service_role;
