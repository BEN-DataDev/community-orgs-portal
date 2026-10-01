-- Organisations created by the full-seed union started self_managed because
-- initialise_organisation_stewardship did not recognise full-seed items as imports
-- (fixed in 20261001025644_seed_merge_review). Nobody holds a role in them, so move
-- each one to unclaimed with an appended stewardship event. Only organisations
-- still at their first revision are touched; anything changed since is left alone.
begin;

create temporary table seed_unclaim on commit drop as
select s.organisation_id, s.revision, i.publication_id
from community_orgs.organisation_stewardship s
join ingestion.full_seed_items i on i.organisation_id = s.organisation_id
  and not i.existing_organisation
where s.state = 'self_managed' and s.revision = 1
  and not exists (select 1 from community_orgs.user_organisation_roles r
    where r.organisation_id = s.organisation_id);

with appended as (
  insert into community_orgs.organisation_stewardship_events(
    organisation_id, revision, previous_state, next_state, actor_id, reason,
    approval_reference, note, related_reference
  )
  select organisation_id, revision + 1, 'self_managed', 'unclaimed', null,
    'Imported publication created an unclaimed organisation',
    null,
    'Correction: the full-seed union recorded this import as self-managed although '
      || 'no organisation representative holds a role. No representative has accepted stewardship.',
    'full-seed-publication:' || publication_id
  from seed_unclaim
  returning organisation_id, event_id
)
update community_orgs.organisation_stewardship s
set state = 'unclaimed', revision = s.revision + 1, current_event_id = a.event_id,
    updated_at = now()
from appended a where s.organisation_id = a.organisation_id;

commit;
