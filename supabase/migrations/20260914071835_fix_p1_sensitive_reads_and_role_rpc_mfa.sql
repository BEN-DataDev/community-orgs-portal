-- Close both P1 findings independently of whether the earlier MFA/guest
-- migrations have reached the target database. Existing permissions remain.
do $migration$
declare
    t text;
begin
    foreach t in array array[
        'contact_info', 'financial_info', 'legal_details', 'dgr_endorsement',
        'documents', 'governance', 'org_members', 'role_audit_log',
        'role_requests', 'user_organisation_roles'
    ] loop
        execute format('alter table community_orgs.%I enable row level security', t);
        execute format('drop policy if exists "sensitive reads require registered user" on community_orgs.%I', t);
        execute format(
            'create policy "sensitive reads require registered user" on community_orgs.%I '
            'as restrictive for select to anon, authenticated '
            'using ((select auth.uid()) is not null '
            'and (select (auth.jwt() ->> ''is_anonymous'')::boolean) is not true)', t);
    end loop;
end
$migration$;

create or replace function community_orgs.user_has_verified_mfa()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from auth.mfa_factors
        where user_id = (select auth.uid())
          and status = 'verified'
    );
$$;

revoke all on function community_orgs.user_has_verified_mfa() from public, anon;
grant execute on function community_orgs.user_has_verified_mfa() to authenticated, service_role;

-- Called only by the SECURITY DEFINER role-management functions below.
-- RLS cannot protect their writes because they execute as the table owner.
create or replace function community_orgs.require_role_management_session()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
    if auth.uid() is null
       or (auth.jwt() ->> 'is_anonymous')::boolean is true then
        raise exception 'A registered account is required' using errcode = '42501';
    end if;

    if community_orgs.user_has_verified_mfa()
       and (auth.jwt() ->> 'aal') is distinct from 'aal2' then
        raise exception 'Multi-factor authentication is required' using errcode = '42501';
    end if;
end;
$function$;

revoke all on function community_orgs.require_role_management_session()
    from public, anon, authenticated;

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
    PERFORM community_orgs.require_role_management_session();

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
    PERFORM community_orgs.require_role_management_session();

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
    PERFORM community_orgs.require_role_management_session();

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
    PERFORM community_orgs.require_role_management_session();

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
