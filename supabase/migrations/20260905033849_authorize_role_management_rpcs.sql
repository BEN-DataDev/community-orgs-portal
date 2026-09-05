-- Gives the role-management RPCs a caller check, so they can be handed back to
-- `authenticated` instead of being unreachable.
--
-- 20260905031617 withdrew EXECUTE from these because they trusted the caller to
-- say who they were: the acting user arrived as a parameter (`p_granted_by`,
-- `p_reviewer_id`) and was written straight into the row. Being SECURITY
-- DEFINER they also bypassed RLS, so the parameter was the only thing standing
-- between an anon caller and any role in any organisation.
--
-- Each function now derives the actor from auth.uid() and ignores the
-- caller-supplied id. The signatures are unchanged so the generated
-- db.types.ts stays valid; the redundant parameters are retained but no longer
-- trusted.
--
-- Two rules are enforced:
--   * the actor must hold `can_manage_members` in the organisation, the same
--     permission `can_edit_org` tests, so RPC authority matches RLS authority;
--   * the actor cannot grant or revoke a role above their own hierarchy level,
--     which stops an admin (3) from minting an owner (4) or unseating one.
--
-- This also corrects the audit-log inserts. They wrote `organisation_id` while
-- role_audit_log has `organization_id`, so every one of these functions aborted
-- on its audit write -- the accident that kept the missing authorization from
-- being exploitable. The column is only safe to fix now that the caller is
-- checked; fixing it alone would have opened the escalation path.

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

    INSERT INTO community_orgs.role_audit_log (user_id, organization_id, role_id, action, performed_by)
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

    INSERT INTO community_orgs.role_audit_log (user_id, organization_id, role_id, action, performed_by, reason)
    VALUES (p_user_id, p_organisation_id, p_role_id, 'revoked', v_actor, p_reason);

    RETURN TRUE;
END;
$function$;

-- A request is always made for yourself. The p_user_id parameter is kept for
-- signature compatibility and must match the caller.
create or replace function community_orgs.request_role(p_user_id uuid, p_organisation_id uuid, p_role_id uuid, p_message text default null::text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_actor uuid := auth.uid();
    v_request_id uuid;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_user_id IS DISTINCT FROM v_actor THEN
        RAISE EXCEPTION 'you may only request a role for yourself';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM community_orgs.roles r WHERE r.id = p_role_id) THEN
        RAISE EXCEPTION 'unknown role';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM community_orgs.organisations o WHERE o.org_id = p_organisation_id) THEN
        RAISE EXCEPTION 'unknown organisation';
    END IF;

    INSERT INTO community_orgs.role_requests (user_id, organisation_id, role_id, message)
    VALUES (v_actor, p_organisation_id, p_role_id, p_message)
    RETURNING id INTO v_request_id;

    RETURN v_request_id;
END;
$function$;

create or replace function community_orgs.process_role_request(p_request_id uuid, p_reviewer_id uuid, p_status text, p_expires_at timestamp with time zone default null::timestamp with time zone)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_actor uuid := auth.uid();
    v_request community_orgs.role_requests%ROWTYPE;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_status NOT IN ('approved', 'rejected') THEN
        RAISE EXCEPTION 'status must be approved or rejected';
    END IF;

    SELECT * INTO v_request FROM community_orgs.role_requests WHERE id = p_request_id;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    IF v_request.status <> 'pending' THEN
        RAISE EXCEPTION 'this request has already been reviewed';
    END IF;

    IF NOT community_orgs.user_has_permission(v_actor, v_request.organisation_id, 'can_manage_members') THEN
        RAISE EXCEPTION 'insufficient privileges to review requests for this organisation';
    END IF;

    UPDATE community_orgs.role_requests
    SET status = p_status, reviewed_by = v_actor, reviewed_at = NOW()
    WHERE id = p_request_id;

    IF p_status = 'approved' THEN
        -- grant_user_role re-checks the actor and the hierarchy ceiling.
        PERFORM community_orgs.grant_user_role(
            v_request.user_id,
            v_request.organisation_id,
            v_request.role_id,
            v_actor,
            p_expires_at
        );
    END IF;

    RETURN TRUE;
END;
$function$;

-- Now that each function establishes its own caller, signed-in users may call
-- them again. `anon` deliberately stays out: every one of them raises on a null
-- auth.uid() anyway.
grant execute on function community_orgs.grant_user_role(uuid, uuid, uuid, uuid, timestamptz) to authenticated;
grant execute on function community_orgs.revoke_user_role(uuid, uuid, uuid, uuid, text) to authenticated;
grant execute on function community_orgs.request_role(uuid, uuid, uuid, text) to authenticated;
grant execute on function community_orgs.process_role_request(uuid, uuid, text, timestamptz) to authenticated;
