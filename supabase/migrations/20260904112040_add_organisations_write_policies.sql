-- `community_orgs.organisations` had row-level security enabled but only
-- SELECT policies. With RLS on and no INSERT policy every insert was rejected,
-- so "Add Organisation" could not succeed regardless of application checks.
--
-- Any signed-in user may create an organisation; admins and owners (anyone
-- holding the `can_manage_members` permission on it) may update it.

drop policy if exists "authenticated users can create organisations"
    on community_orgs.organisations;

create policy "authenticated users can create organisations"
    on community_orgs.organisations
    for insert
    to authenticated
    with check (auth.uid() is not null);

drop policy if exists "organisation admins can update their organisation"
    on community_orgs.organisations;

create policy "organisation admins can update their organisation"
    on community_orgs.organisations
    for update
    to authenticated
    using (
        community_orgs.user_has_permission(auth.uid(), org_id, 'can_manage_members')
    )
    with check (
        community_orgs.user_has_permission(auth.uid(), org_id, 'can_manage_members')
    );
