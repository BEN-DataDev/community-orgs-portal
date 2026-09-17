-- P08: scoped assignments and ownership safeguards.
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
    -- Serialise membership changes before resolving actor/target authority.
    PERFORM 1 FROM community_orgs.organisations WHERE org_id=p_organisation_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'unknown organisation'; END IF;

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

    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id=p_user_id AND is_anonymous IS NOT TRUE) THEN
        RAISE EXCEPTION 'target must be a registered account';
    END IF;
    IF community_orgs.user_max_role_level(p_user_id,p_organisation_id)
       > community_orgs.user_max_role_level(v_actor,p_organisation_id) THEN
        RAISE EXCEPTION 'cannot change assignments for someone ranked above you';
    END IF;
    IF p_expires_at IS NOT NULL AND (NOT isfinite(p_expires_at) OR p_expires_at <= now()) THEN
        RAISE EXCEPTION 'expiry must be in the future';
    END IF;
    IF v_target_level = 4 AND p_expires_at IS NOT NULL THEN
        RAISE EXCEPTION 'owner assignments must not expire';
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
    -- Serialise membership changes before resolving actor/target authority.
    PERFORM 1 FROM community_orgs.organisations WHERE org_id=p_organisation_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'unknown organisation'; END IF;

    IF NOT community_orgs.user_has_permission(v_actor, p_organisation_id, 'can_manage_members') THEN
        RAISE EXCEPTION 'insufficient privileges to manage members of this organisation';
    END IF;

    IF community_orgs.user_max_role_level(p_user_id, p_organisation_id)
       > community_orgs.user_max_role_level(v_actor, p_organisation_id) THEN
        RAISE EXCEPTION 'cannot revoke a role from someone ranked above you';
    END IF;

    IF p_user_id = v_actor THEN RAISE EXCEPTION 'you cannot revoke your own assignments'; END IF;
    IF EXISTS (SELECT 1 FROM community_orgs.roles WHERE id=p_role_id AND hierarchy_level > community_orgs.user_max_role_level(v_actor,p_organisation_id)) THEN
        RAISE EXCEPTION 'cannot revoke a role above your own';
    END IF;
    IF EXISTS (SELECT 1 FROM community_orgs.user_organisation_roles u JOIN community_orgs.roles r ON r.id=u.role_id
        WHERE u.user_id=p_user_id AND u.organisation_id=p_organisation_id AND u.role_id=p_role_id
          AND u.is_active AND (u.expires_at IS NULL OR u.expires_at>now()) AND r.hierarchy_level=4)
       AND NOT EXISTS (SELECT 1 FROM community_orgs.user_organisation_roles u JOIN community_orgs.roles r ON r.id=u.role_id
        WHERE u.organisation_id=p_organisation_id AND u.user_id<>p_user_id AND u.is_active
          AND u.expires_at IS NULL AND r.hierarchy_level=4) THEN
        RAISE EXCEPTION 'grant another non-expiring owner before revoking this owner';
    END IF;
    IF length(p_reason)>1000 THEN RAISE EXCEPTION 'reason is too long'; END IF;

    UPDATE community_orgs.user_organisation_roles
    SET is_active = false, updated_at = NOW()
    WHERE user_id = p_user_id
    AND organisation_id = p_organisation_id
    AND role_id = p_role_id AND is_active;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    INSERT INTO community_orgs.role_audit_log (user_id, organisation_id, role_id, action, performed_by, reason)
    VALUES (p_user_id, p_organisation_id, p_role_id, 'revoked', v_actor, p_reason);

    RETURN TRUE;
END;
$function$;


-- Assignment data is private and requires the same session and scope as writes.
create function community_orgs.organisation_role_assignments(p_organisation_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_level integer; v_name text;
begin
 perform community_orgs.require_role_management_session();
 if not community_orgs.user_has_permission(auth.uid(),p_organisation_id,'can_manage_members') then
   raise exception 'Organisation role management access required' using errcode='42501';
 end if;
 select entity_name into v_name from community_orgs.organisations where org_id=p_organisation_id;
 if not found then raise exception 'unknown organisation'; end if;
 v_level:=community_orgs.user_max_role_level(auth.uid(),p_organisation_id);
 return jsonb_build_object('name',v_name,'level',v_level,
 'roles',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'level',hierarchy_level) order by hierarchy_level)
   from community_orgs.roles where hierarchy_level between 1 and v_level),'[]'::jsonb),
 'assignments',coalesce((select jsonb_agg(jsonb_build_object(
   'id',u.id,'userId',u.user_id,'roleId',u.role_id,'role',r.name,'level',r.hierarchy_level,
   'active',u.is_active,'expiresAt',u.expires_at,'grantedAt',u.granted_at,
   'status',case when not u.is_active then 'Revoked' when u.expires_at<=now() then 'Expired' else 'Active' end,
   'canRevoke',u.is_active and u.user_id<>auth.uid() and r.hierarchy_level<=v_level
      and community_orgs.user_max_role_level(u.user_id,p_organisation_id)<=v_level
 ) order by u.user_id,r.hierarchy_level desc)
 from community_orgs.user_organisation_roles u join community_orgs.roles r on r.id=u.role_id
 where u.organisation_id=p_organisation_id),'[]'::jsonb));
end $$;
revoke all on function community_orgs.organisation_role_assignments(uuid) from public,anon;
grant execute on function community_orgs.organisation_role_assignments(uuid) to authenticated;
-- No browser write path may bypass the RPC hierarchy, audit or continuity checks.
revoke insert,update,delete on community_orgs.user_organisation_roles from anon,authenticated;
