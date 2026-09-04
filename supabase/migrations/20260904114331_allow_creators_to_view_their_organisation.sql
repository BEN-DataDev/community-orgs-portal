-- `INSERT ... RETURNING` is checked against the SELECT policy, and the owner
-- role is granted by an AFTER INSERT trigger that has not run at that point. So
-- creating a private organisation and returning the new row failed with
-- "new row violates row-level security policy", even though the insert itself
-- was allowed.
--
-- This also means a creator never loses sight of their own record if a role
-- grant is later revoked or expires.
drop policy if exists "creators can view their organisations" on community_orgs.organisations;

create policy "creators can view their organisations"
    on community_orgs.organisations
    for select
    to authenticated
    using (inserted_by = auth.uid());
