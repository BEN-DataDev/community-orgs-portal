-- Finishes the UK/US spelling cleanup the role-management work kept deferring.
--
-- The schema is Australian throughout -- organisations, user_organisation_roles,
-- role_requests.organisation_id, set_organisation_slug, get_initials_with_colour
-- -- with one exception: role_audit_log.organization_id, the only US-spelled
-- column of the 231 in community_orgs. 20260905033849 and 20260905033925 both
-- noted it and both bent the *functions* to match the column, because renaming
-- it while those functions were still unauthorised would have been the wrong
-- order of work. The functions now derive their actor from auth.uid(), so the
-- column can be brought into line.
--
-- Three things ride along:
--
--   * The FK constraints on organisations are still named organizations_*_fkey,
--     inherited from the table's original US name. The baseline calls this out
--     as a deliberate departure it chose not to fix.
--   * set_organization_slug() is dead code. Only set_organisation_slug() is
--     wired to organisation_slug_trigger; the US-spelled twin reads NEW.name,
--     but the column is entity_name, so it would raise if it ever fired.
--     20260905031617 already withdrew EXECUTE and locked its search_path rather
--     than dropping it. Nothing references it now.
--   * The audit-log read policy names the column in its USING expression.
--     Postgres stores that as a parsed reference to the attribute, not as text,
--     so the rename carries it along and the policy needs no restatement.
--
-- No index, default or check constraint touches the column, so the rename is
-- metadata-only.

-- 1. The dead US-spelled slug trigger function.

drop function if exists community_orgs.set_organization_slug();

-- 2. The column.

alter table community_orgs.role_audit_log
    rename column organization_id to organisation_id;

-- 3. Constraint names. Renaming a column leaves the constraint's *name* alone,
--    so these are separate statements; none of them re-validates the data.

alter table community_orgs.role_audit_log
    rename constraint role_audit_log_organization_id_fkey
    to role_audit_log_organisation_id_fkey;

alter table community_orgs.organisations
    rename constraint organizations_inserted_by_fkey
    to organisations_inserted_by_fkey;

alter table community_orgs.organisations
    rename constraint organizations_last_edited_by_fkey
    to organisations_last_edited_by_fkey;

-- 4. The three function bodies that write the column. plpgsql bodies are
--    resolved at execution time, so an unreplaced one would now fail on its
--    audit write -- the same silent breakage 20260905033849 was correcting,
--    only in the opposite direction.
--
--    Each is reproduced verbatim from its defining migration with the single
--    column reference changed. `create or replace` preserves the existing
--    EXECUTE grants, so the authorisation surface is untouched: grant_user_role
--    and revoke_user_role stay available to `authenticated`, expire_roles stays
--    revoked from everyone but service_role.

create or replace function community_orgs.grant_user_role(p_user_id uuid, p_organisation_id uuid, p_role_id uuid, p_granted_by uuid, p_expires_at timestamp with time zone default null::timestamp with time zone)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_actor uuid := auth.uid();
    v_role_assignment_id uuid;
    v_target_level integer;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF NOT community_orgs.user_has_permission(v_actor, p_organisation_id, 'can_manage_members') THEN
        RAISE EXCEPTION 'insufficient privileges to manage members of this organisation';
    END IF;

    SELECT r.hierarchy_level INTO v_target_level
    FROM community_orgs.roles r WHERE r.id = p_role_id;

    IF v_target_level IS NULL THEN
        RAISE EXCEPTION 'unknown role';
    END IF;

    IF v_target_level > community_orgs.user_max_role_level(v_actor, p_organisation_id) THEN
        RAISE EXCEPTION 'cannot grant a role above your own';
    END IF;

    INSERT INTO community_orgs.user_organisation_roles (user_id, organisation_id, role_id, granted_by, expires_at)
    VALUES (p_user_id, p_organisation_id, p_role_id, v_actor, p_expires_at)
    ON CONFLICT (user_id, organisation_id, role_id)
    DO UPDATE SET
        is_active = true,
        granted_by = v_actor,
        expires_at = p_expires_at,
        updated_at = NOW()
    RETURNING id INTO v_role_assignment_id;

    INSERT INTO community_orgs.role_audit_log (user_id, organisation_id, role_id, action, performed_by)
    VALUES (p_user_id, p_organisation_id, p_role_id, 'granted', v_actor);

    RETURN v_role_assignment_id;
END;
$function$;

create or replace function community_orgs.revoke_user_role(p_user_id uuid, p_organisation_id uuid, p_role_id uuid, p_revoked_by uuid, p_reason text default null::text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_actor uuid := auth.uid();
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF NOT community_orgs.user_has_permission(v_actor, p_organisation_id, 'can_manage_members') THEN
        RAISE EXCEPTION 'insufficient privileges to manage members of this organisation';
    END IF;

    IF community_orgs.user_max_role_level(p_user_id, p_organisation_id)
       > community_orgs.user_max_role_level(v_actor, p_organisation_id) THEN
        RAISE EXCEPTION 'cannot revoke a role from someone ranked above you';
    END IF;

    UPDATE community_orgs.user_organisation_roles
    SET is_active = false, updated_at = NOW()
    WHERE user_id = p_user_id
    AND organisation_id = p_organisation_id
    AND role_id = p_role_id;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    INSERT INTO community_orgs.role_audit_log (user_id, organisation_id, role_id, action, performed_by, reason)
    VALUES (p_user_id, p_organisation_id, p_role_id, 'revoked', v_actor, p_reason);

    RETURN TRUE;
END;
$function$;

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
            (user_id, organisation_id, role_id, action, performed_by)
        SELECT user_id, organisation_id, role_id, 'expired', NULL
        FROM expired
        RETURNING 1
    )
    SELECT count(*) INTO v_expired_count FROM logged;

    RETURN v_expired_count;
END;
$function$;
