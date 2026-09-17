-- The legacy baseline SELECT policy only checked is_active, so its permissive
-- OR branch let expired assignments read private organisation rows. Reuse the
-- same expiry-aware helper used by child records and platform administration.
-- Existing public and creator read policies remain independent grants.
drop policy if exists "organisation members can view private organisations"
 on community_orgs.organisations;
create policy "organisation members can view private organisations"
 on community_orgs.organisations for select
 using (community_orgs.can_view_org(org_id));
