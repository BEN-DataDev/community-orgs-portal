-- `community_orgs.organisations` and `community_orgs.user_organisation_roles`
-- returned HTTP 500 for every read:
--
--   42P17: infinite recursion detected in policy for relation
--          "user_organisation_roles"
--
-- The old policy queried user_organisation_roles from inside a policy ON
-- user_organisation_roles, so Postgres re-entered the same policy evaluating
-- it. `organisations` inherited the fault because its "members can view private
-- organisations" policy also selects from that table.
--
-- community_orgs.user_has_permission(p_user_id, p_organisation_id, p_permission)
-- is SECURITY DEFINER, so calling it does not re-enter row-level security.

drop policy if exists "organisation admins can view all roles in their organisation"
    on community_orgs.user_organisation_roles;

create policy "organisation admins can view all roles in their organisation"
    on community_orgs.user_organisation_roles
    for select
    using (
        community_orgs.user_has_permission(
            auth.uid(),
            organisation_id,
            'can_manage_members'
        )
    );
