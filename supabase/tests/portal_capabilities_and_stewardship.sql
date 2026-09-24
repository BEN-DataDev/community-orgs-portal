begin;

create function pg_temp.refused(command text) returns void language plpgsql as $$
begin
  begin execute command;
  exception when others then return;
  end;
  raise exception 'Unexpected success: %', command;
end
$$;

insert into auth.users(id) values
  ('00000000-0000-4000-8000-000000004201'),
  ('00000000-0000-4000-8000-000000004202'),
  ('00000000-0000-4000-8000-000000004203'),
  ('00000000-0000-4000-8000-000000004204');

insert into portal.capability_appointments(
  user_id, capability, appointed_by, reason, approval_reference, origin
) values
  ('00000000-0000-4000-8000-000000004201', 'portal_administrator', null,
   'Phase 2 test bootstrap', 'TEST-BOOTSTRAP-1', 'bootstrap'),
  ('00000000-0000-4000-8000-000000004203', 'data_steward', null,
   'Phase 2 test steward', 'TEST-STEWARD-1', 'bootstrap');

select set_config('request.jwt.claims', '{}', true);
insert into community_orgs.organisations(org_id, entity_name, slug, is_public) values
  ('00000000-0000-4000-8000-000000004211', 'Unclaimed fixture', 'phase2-unclaimed', false),
  ('00000000-0000-4000-8000-000000004212', 'Managed fixture', 'phase2-managed', false);

do $$
declare
  administrator uuid := '00000000-0000-4000-8000-000000004201';
  second_administrator uuid := '00000000-0000-4000-8000-000000004202';
  steward uuid := '00000000-0000-4000-8000-000000004203';
  outsider uuid := '00000000-0000-4000-8000-000000004204';
  unclaimed uuid := '00000000-0000-4000-8000-000000004211';
  managed uuid := '00000000-0000-4000-8000-000000004212';
  first_appointment uuid;
  second_appointment uuid;
  event_id bigint;
begin
  select appointment_id into first_appointment
  from portal.capability_appointments
  where user_id = administrator and capability = 'portal_administrator';

  set local role authenticated;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', administrator, 'aal', 'aal1')::text, true);
  if not community_orgs.is_portal_administrator()
     or community_orgs.is_data_steward()
     or community_orgs.is_ingestion_operator() then
    raise exception 'Portal Administrator and Data Steward capabilities were not separated';
  end if;
  if not community_orgs.portal_administrator_can_edit_organisation(unclaimed)
     or community_orgs.user_max_role_level(administrator, unclaimed) <> 4
     or not community_orgs.can_edit_org(unclaimed) then
    raise exception 'Unclaimed automatic edit authority missing';
  end if;

  event_id := community_orgs.set_organisation_stewardship(
    unclaimed, 'self_managed', 'Owner accepted responsibility', 'TEST-HANDOFF-1',
    'Synthetic handoff in the same authenticated session.', null, 1
  );
  if event_id is null
     or community_orgs.portal_administrator_can_edit_organisation(unclaimed)
     or community_orgs.user_max_role_level(administrator, unclaimed) <> 0
     or community_orgs.can_edit_org(unclaimed) then
    raise exception 'Self-managed handoff did not immediately remove automatic authority';
  end if;

  perform community_orgs.set_organisation_stewardship(
    managed, 'portal_managed', 'Continuing management authorised', 'TEST-MANAGED-1',
    'Synthetic explicit authority.', null, 1
  );
  if not community_orgs.portal_administrator_can_edit_organisation(managed)
     or not community_orgs.can_edit_org(managed) then
    raise exception 'Explicit portal-managed authority missing';
  end if;
  perform community_orgs.set_organisation_stewardship(
    managed, 'invitation_pending', 'Invitation issued', null,
    'Synthetic invitation-pending state.', 'TEST-INVITATION-1', 2
  );
  perform pg_temp.refused(format(
    'select community_orgs.set_organisation_stewardship(%L,''portal_managed'',''Expired'',''TEST-BAD'',''Must fail'',null,3)',
    managed
  ));
  perform community_orgs.set_organisation_stewardship(
    managed, 'unclaimed', 'Invitation cancelled', null,
    'Cancellation grants no continuing authority.', 'TEST-INVITATION-1', 3
  );

  second_appointment := community_orgs.appoint_portal_capability(
    second_administrator, 'portal_administrator', 'Continuity administrator',
    'TEST-ADMIN-2', now(), null
  );
  if second_appointment is null then raise exception 'Second appointment missing'; end if;
  if not community_orgs.revoke_portal_capability(
    first_appointment, 'Bootstrap handoff complete', 'TEST-REVOKE-1'
  ) then raise exception 'Appointment revocation failed'; end if;
  if community_orgs.is_portal_administrator()
     or community_orgs.portal_administrator_can_edit_organisation(managed) then
    raise exception 'Revocation did not affect the existing session immediately';
  end if;
  perform pg_temp.refused(format(
    'select community_orgs.set_organisation_stewardship(%L,''co_managed'',''No access'',''TEST'',''Must fail'')',
    managed
  ));

  perform set_config('request.jwt.claims', jsonb_build_object('sub', steward, 'aal', 'aal1')::text, true);
  if not community_orgs.is_data_steward()
     or not community_orgs.is_ingestion_operator()
     or community_orgs.is_portal_administrator()
     or community_orgs.can_edit_org(managed) then
    raise exception 'Data Steward capability leaked governance or organisation authority';
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', outsider, 'aal', 'aal1')::text, true);
  if community_orgs.is_portal_administrator() or community_orgs.is_data_steward() then
    raise exception 'Unappointed account received a portal capability';
  end if;
  perform pg_temp.refused(format(
    'insert into portal.capability_appointments(user_id,capability,appointed_by,reason,approval_reference) values(%L,''portal_administrator'',%L,''self'',''TEST'')',
    outsider, outsider
  ));
  perform pg_temp.refused(format(
    'update community_orgs.organisation_stewardship set state=''portal_managed'' where organisation_id=%L',
    managed
  ));
  reset role;

  perform pg_temp.refused(format(
    'update portal.capability_appointments set reason=''rewritten'' where appointment_id=%L',
    second_appointment
  ));
  perform pg_temp.refused(format(
    'delete from portal.capability_appointment_events where appointment_id=%L',
    second_appointment
  ));
  perform pg_temp.refused(format(
    'update community_orgs.organisation_stewardship_events set note=''rewritten'' where organisation_id=%L',
    managed
  ));
  if (select count(*) from community_orgs.organisation_stewardship_events
      where organisation_id = managed) <> 4 then
    raise exception 'Stewardship event history is incomplete';
  end if;
end
$$;

rollback;

select 'Explicit portal capabilities, retained revocation and stewardship handoff passed' as result;
