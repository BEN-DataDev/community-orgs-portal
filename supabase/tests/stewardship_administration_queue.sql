begin;

create function pg_temp.refused(command text) returns void language plpgsql as $$
begin
  begin execute command;
  exception when others then return;
  end;
  raise exception 'Unexpected success: %', command;
end
$$;

insert into auth.users(id,email,email_confirmed_at,created_at,updated_at) values
  ('00000000-0000-4000-8000-000000004501','queue-admin@example.invalid',now(),now(),now()),
  ('00000000-0000-4000-8000-000000004502','queue-outsider@example.invalid',now(),now(),now());
insert into portal.capability_appointments(
  user_id,capability,appointed_by,reason,approval_reference,origin
) values (
  '00000000-0000-4000-8000-000000004501','portal_administrator',null,
  'Phase 4 administration queue test','TEST-PHASE4-QUEUE','bootstrap'
);

select set_config('request.jwt.claims','{}',true);
insert into community_orgs.organisations(org_id,entity_name,slug,is_public) values
  ('00000000-0000-4000-8000-000000004511','Queue unclaimed fixture','queue-unclaimed-fixture',false),
  ('00000000-0000-4000-8000-000000004512','Queue expiry fixture','queue-expiry-fixture',false);
insert into community_orgs.organisation_invitations(
  invitation_id,organisation_id,email,target_stewardship,invited_at,expires_at,
  invited_by,reason,approval_reference,note
) values (
  '00000000-0000-4000-8000-000000004521',
  '00000000-0000-4000-8000-000000004512','recipient@example.invalid','self_managed',
  now()-interval '2 days',now()-interval '1 day','00000000-0000-4000-8000-000000004501',
  'Expired queue fixture','TEST-QUEUE-EXPIRY','Must expire without a grant.'
);
insert into community_orgs.organisation_invitation_events(
  invitation_id,event_type,actor_id,reason
) values (
  '00000000-0000-4000-8000-000000004521','issued',
  '00000000-0000-4000-8000-000000004501','Expired queue fixture'
);

do $$
declare result jsonb;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000004502","aal":"aal1"}',true);
  perform pg_temp.refused(
    'select community_orgs.stewardship_administration_queue('''','''','''',0)'
  );

  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000004501","aal":"aal1"}',true);
  perform community_orgs.set_organisation_stewardship(
    '00000000-0000-4000-8000-000000004512','invitation_pending',
    'Expired queue fixture',null,'Pending expired handoff.',
    '00000000-0000-4000-8000-000000004521',1
  );
  result := community_orgs.stewardship_administration_queue('Queue','unclaimed','expired',0);
  if (result->>'stewardshipTotal')::integer <> 2
     or (result->>'invitationTotal')::integer <> 1
     or jsonb_array_length(result->'organisations') <> 2
     or jsonb_array_length(result->'invitations') <> 1
     or result->'invitations'->0->>'status' <> 'expired'
     or exists (
       select 1 from community_orgs.user_organisation_roles
       where organisation_id='00000000-0000-4000-8000-000000004512'
     ) then
    raise exception 'Administration queue filtering or no-grant expiry failed: %',result;
  end if;
end
$$;

rollback;
select 'Stewardship and invitation administration queue passed' as result;
