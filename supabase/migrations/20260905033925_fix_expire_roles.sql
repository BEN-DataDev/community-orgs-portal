-- expire_roles() has never worked. Two independent faults, both of which abort
-- the call:
--
--   * it schema-qualified its own CTE -- `FROM community_orgs.expired_roles` --
--     which resolves to nothing, since a CTE lives in the query, not a schema;
--   * it inserted `organisation_id` into role_audit_log, which has
--     `organization_id`. The same UK/US slip as the role RPCs.
--
-- The practical effect was narrower than it looks: can_view_org, can_edit_org
-- and user_has_permission all test `expires_at > now()` directly, so an expired
-- role already stops granting access. What was missing is the bookkeeping --
-- is_active stayed true and no 'expired' audit rows were ever written.
--
-- EXECUTE stays revoked from anon and authenticated: this is a maintenance
-- routine for service_role, or for pg_cron if it is ever scheduled.

create or replace function community_orgs.expire_roles()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_expired_count integer;
BEGIN
    WITH expired AS (
        UPDATE community_orgs.user_organisation_roles
        SET is_active = false, updated_at = NOW()
        WHERE expires_at < NOW() AND is_active = true
        RETURNING user_id, organisation_id, role_id
    ),
    logged AS (
        INSERT INTO community_orgs.role_audit_log
            (user_id, organization_id, role_id, action, performed_by)
        SELECT user_id, organisation_id, role_id, 'expired', NULL
        FROM expired
        RETURNING 1
    )
    SELECT count(*) INTO v_expired_count FROM logged;

    RETURN v_expired_count;
END;
$function$;

revoke execute on function community_orgs.expire_roles() from public, anon, authenticated;
