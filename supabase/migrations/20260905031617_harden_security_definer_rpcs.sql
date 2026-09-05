-- Hardens the SECURITY DEFINER functions carried over in the baseline.
--
-- Two independent problems, both reachable because `community_orgs` is an
-- exposed PostgREST schema and the baseline grants EXECUTE on every function in
-- it to `anon` and `authenticated`:
--
--   1. The role-management RPCs take the acting user as a *parameter*
--      (`p_granted_by`, `p_reviewer_id`) and never consult `auth.uid()`. Being
--      SECURITY DEFINER they also bypass RLS.
--
--      `request_role` was exploitable as it stood: calling it as `anon`
--      inserted a row into `role_requests` that RLS would have refused.
--
--      `grant_user_role` / `revoke_user_role` / `process_role_request` failed
--      closed only by accident — they abort writing the audit row, because the
--      body says `organisation_id` while role_audit_log has `organization_id`.
--      The role INSERT itself is not refused by RLS; only the later abort rolls
--      it back. Correcting that spelling on its own would therefore hand any
--      anon-key holder the ability to grant themselves any role in any
--      organisation. Fix the authorization before fixing the column.
--
--      Nothing in src/ calls any of them — the only mention is the generated
--      db.types.ts — so EXECUTE is withdrawn rather than rewritten to check
--      the caller.
--
--   2. Ten functions were SECURITY DEFINER with a mutable search_path, the
--      condition Supabase's linter flags as `function_search_path_mutable`.
--
-- The blanket default privilege is narrowed too, so a function added later is
-- not automatically executable by `anon`.
--
-- Each REVOKE names `public` as well as the two API roles. Postgres grants
-- EXECUTE on every new function to PUBLIC implicitly, so revoking from `anon`
-- alone leaves the privilege in place through PUBLIC and changes nothing —
-- confirmed with has_function_privilege() before and after. `service_role`
-- keeps its own explicit grant from the baseline and is unaffected.

-- ---------------------------------------------------------------------------
-- 1. Withdraw EXECUTE on the privileged role-management RPCs
-- ---------------------------------------------------------------------------

revoke execute on function community_orgs.grant_user_role(uuid, uuid, uuid, uuid, timestamptz) from public, anon, authenticated;
revoke execute on function community_orgs.revoke_user_role(uuid, uuid, uuid, uuid, text) from public, anon, authenticated;
revoke execute on function community_orgs.process_role_request(uuid, uuid, text, timestamptz) from public, anon, authenticated;
revoke execute on function community_orgs.request_role(uuid, uuid, uuid, text) from public, anon, authenticated;

-- Legacy duplicates that reference columns this schema does not have
-- (`organisations.id`, `organisations.name`; the table has `org_id` and
-- `entity_name`). They raise at runtime, so nothing can be relying on them.
revoke execute on function community_orgs.set_organization_slug() from public, anon, authenticated;
revoke execute on function community_orgs.get_user_all_roles(uuid) from public, anon, authenticated;
revoke execute on function community_orgs.get_user_organisations_with_roles(uuid) from public, anon, authenticated;

-- Stop the next function added here from being world-executable by default.
alter default privileges in schema community_orgs
    revoke execute on functions from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Lock the search_path on every remaining SECURITY DEFINER function
-- ---------------------------------------------------------------------------
-- pg_catalog is always searched implicitly, so now()/coalesce()/lower() and the
-- aggregates keep resolving; every community_orgs reference in these bodies is
-- already schema-qualified apart from the two rewritten below.

alter function community_orgs.set_organization_slug() set search_path = '';
alter function community_orgs.user_has_permission(uuid, uuid, text) set search_path = '';
alter function community_orgs.user_max_role_level(uuid, uuid) set search_path = '';
alter function community_orgs.get_user_all_roles(uuid) set search_path = '';
alter function community_orgs.get_user_organisations_with_roles(uuid) set search_path = '';
alter function community_orgs.grant_user_role(uuid, uuid, uuid, uuid, timestamptz) set search_path = '';
alter function community_orgs.revoke_user_role(uuid, uuid, uuid, uuid, text) set search_path = '';
alter function community_orgs.request_role(uuid, uuid, uuid, text) set search_path = '';

-- `FROM roles r2` was unqualified: under a locked search_path it no longer
-- resolves, and under a mutable one it was the hijack vector.
create or replace function community_orgs.user_has_inherited_permission(p_user_id uuid, p_organisation_id uuid, p_permission text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM community_orgs.user_organisation_roles uor
        JOIN community_orgs.roles r ON uor.role_id = r.id
        WHERE uor.user_id = p_user_id
        AND uor.organisation_id = p_organisation_id
        AND uor.is_active = true
        AND (uor.expires_at IS NULL OR uor.expires_at > NOW())
        AND (
            r.permissions->>p_permission = 'true' OR
            r.hierarchy_level >= (
                SELECT MIN(r2.hierarchy_level)
                FROM community_orgs.roles r2
                WHERE r2.permissions->>p_permission = 'true'
            )
        )
    );
END;
$function$;

revoke execute on function community_orgs.user_has_inherited_permission(uuid, uuid, text) from public, anon, authenticated;

-- `PERFORM grant_user_role(...)` was likewise unqualified.
create or replace function community_orgs.process_role_request(p_request_id uuid, p_reviewer_id uuid, p_status text, p_expires_at timestamp with time zone default null::timestamp with time zone)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_request community_orgs.role_requests%ROWTYPE;
BEGIN
    SELECT * INTO v_request FROM community_orgs.role_requests WHERE id = p_request_id;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    UPDATE community_orgs.role_requests
    SET status = p_status, reviewed_by = p_reviewer_id, reviewed_at = NOW()
    WHERE id = p_request_id;

    IF p_status = 'approved' THEN
        PERFORM community_orgs.grant_user_role(
            v_request.user_id,
            v_request.organisation_id,
            v_request.role_id,
            p_reviewer_id,
            p_expires_at
        );
    END IF;

    RETURN TRUE;
END;
$function$;

revoke execute on function community_orgs.process_role_request(uuid, uuid, text, timestamptz) from public, anon, authenticated;
