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
  ('00000000-0000-4000-8000-000000004301','administrator@example.invalid',now(),now(),now()),
  ('00000000-0000-4000-8000-000000004302','owner@example.invalid',now(),now(),now()),
  ('00000000-0000-4000-8000-000000004303','other@example.invalid',now(),now(),now()),
  ('00000000-0000-4000-8000-000000004304','unverified@example.invalid',null,now(),now());

insert into portal.capability_appointments(
  user_id, capability, appointed_by, reason, approval_reference, origin
) values (
  '00000000-0000-4000-8000-000000004301', 'portal_administrator', null,
  'Invitation test administrator', 'TEST-INVITE-ADMIN', 'bootstrap'
);

select set_config('request.jwt.claims', '{}', true);
insert into community_orgs.organisations(org_id,entity_name,slug,is_public) values
  ('00000000-0000-4000-8000-000000004311','Invitation acceptance fixture','invitation-acceptance-fixture',false),
  ('00000000-0000-4000-8000-000000004312','Invitation cancellation fixture','invitation-cancellation-fixture',false),
  ('00000000-0000-4000-8000-000000004313','Invitation expiry fixture','invitation-expiry-fixture',false);

do $$
declare
  administrator uuid := '00000000-0000-4000-8000-000000004301';
  owner_account uuid := '00000000-0000-4000-8000-000000004302';
  other_account uuid := '00000000-0000-4000-8000-000000004303';
  unverified_account uuid := '00000000-0000-4000-8000-000000004304';
  accept_org uuid := '00000000-0000-4000-8000-000000004311';
  cancel_org uuid := '00000000-0000-4000-8000-000000004312';
  expiry_org uuid := '00000000-0000-4000-8000-000000004313';
  accept_invitation uuid;
  cancel_invitation uuid;
  expiry_invitation uuid := '00000000-0000-4000-8000-000000004321';
  result jsonb;
  expiry_event bigint;
  first_cancellation boolean;
  replay_cancellation boolean;
  cancellation_state community_orgs.stewardship_state;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', administrator, 'aal', 'aal1')::text, true);
  accept_invitation := community_orgs.issue_organisation_invitation(
    accept_org, ' Owner@Example.Invalid ', 'self_managed',
    'Representative approved', 'TEST-OWNER-APPROVAL-1',
    'Accepting transfers stewardship to the representative.', now() + interval '7 days'
  );
  if (select state from community_orgs.organisation_stewardship where organisation_id=accept_org)
       <> 'invitation_pending'
     or (select email from community_orgs.organisation_invitations where invitation_id=accept_invitation)
       <> 'owner@example.invalid' then
    raise exception 'Issuance did not create normalised terms and pending stewardship';
  end if;
  perform pg_temp.refused(format(
    'select community_orgs.issue_organisation_invitation(%L,''second@example.invalid'',''self_managed'',''duplicate'',''TEST'',''must fail'',now()+interval ''1 day'')',
    accept_org
  ));

  perform set_config('request.jwt.claims', jsonb_build_object('sub', other_account, 'aal', 'aal1')::text, true);
  perform pg_temp.refused(format(
    'select community_orgs.accept_organisation_invitation(%L)', accept_invitation
  ));
  if exists (select 1 from community_orgs.user_organisation_roles where organisation_id=accept_org) then
    raise exception 'Email mismatch granted an owner role';
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', unverified_account, 'aal', 'aal1')::text, true);
  perform pg_temp.refused(format(
    'select community_orgs.accept_organisation_invitation(%L)', accept_invitation
  ));

  perform set_config('request.jwt.claims', jsonb_build_object('sub', owner_account, 'aal', 'aal1')::text, true);
  result := community_orgs.accept_organisation_invitation(accept_invitation);
  if result->>'status' <> 'accepted'
     or (select state from community_orgs.organisation_stewardship where organisation_id=accept_org)
       <> 'self_managed'
     or not exists (
       select 1 from community_orgs.user_organisation_roles u
       join community_orgs.roles r on r.id=u.role_id
       where u.user_id=owner_account and u.organisation_id=accept_org
         and u.is_active and u.expires_at is null and r.hierarchy_level=4
     ) then
    raise exception 'Acceptance did not atomically grant ownership and stewardship';
  end if;
  result := community_orgs.accept_organisation_invitation(accept_invitation);
  if result->>'status' <> 'accepted'
     or (select count(*) from community_orgs.organisation_invitation_events
         where invitation_id=accept_invitation and event_type='accepted') <> 1
     or (select count(*) from community_orgs.role_audit_log
         where organisation_id=accept_org and user_id=owner_account and action='granted') <> 1 then
    raise exception 'Accepted invitation was replayable';
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', administrator, 'aal', 'aal1')::text, true);
  if community_orgs.portal_administrator_can_edit_organisation(accept_org) then
    raise exception 'Self-managed acceptance did not remove automatic administrator authority';
  end if;
  cancel_invitation := community_orgs.issue_organisation_invitation(
    cancel_org, 'owner@example.invalid', 'co_managed', 'Co-management approved',
    'TEST-CO-MANAGED-1', 'This offer can be cancelled.', now() + interval '7 days'
  );
  first_cancellation := community_orgs.cancel_organisation_invitation(
    cancel_invitation, 'Representative withdrew'
  );
  replay_cancellation := community_orgs.cancel_organisation_invitation(cancel_invitation, 'Replay');
  select state into cancellation_state from community_orgs.organisation_stewardship
  where organisation_id=cancel_org;
  if not first_cancellation or replay_cancellation or cancellation_state <> 'unclaimed'
     or exists (select 1 from community_orgs.user_organisation_roles where organisation_id=cancel_org) then
    raise exception 'Cancellation failed: first %, replay %, state %',
      first_cancellation, replay_cancellation, cancellation_state;
  end if;

  insert into community_orgs.organisation_invitations(
    invitation_id,organisation_id,email,target_stewardship,invited_at,expires_at,
    invited_by,reason,approval_reference,note
  ) values (
    expiry_invitation,expiry_org,'owner@example.invalid','self_managed',
    now()-interval '2 days',now()-interval '1 day',administrator,
    'Expired fixture','TEST-EXPIRED-1','Must grant nothing.'
  );
  insert into community_orgs.organisation_invitation_events(
    invitation_id,event_type,actor_id,reason
  ) values (expiry_invitation,'issued',administrator,'Expired fixture');
  select * into expiry_event from community_orgs.set_organisation_stewardship(
    expiry_org,'invitation_pending','Expired fixture',null,'Pending expired fixture',
    expiry_invitation::text,1
  );

  perform set_config('request.jwt.claims', jsonb_build_object('sub', owner_account, 'aal', 'aal1')::text, true);
  result := community_orgs.accept_organisation_invitation(expiry_invitation);
  if result->>'status' <> 'expired'
     or (select state from community_orgs.organisation_stewardship where organisation_id=expiry_org)
       <> 'unclaimed'
     or exists (select 1 from community_orgs.user_organisation_roles where organisation_id=expiry_org)
     or (select count(*) from community_orgs.organisation_invitation_events
         where invitation_id=expiry_invitation and event_type='expired') <> 1 then
    raise exception 'Expiry did not record a terminal no-grant outcome';
  end if;

  set local role authenticated;
  perform pg_temp.refused(format(
    'insert into community_orgs.organisation_invitations(organisation_id,email,target_stewardship,expires_at,invited_by,reason,approval_reference,note) values(%L,''owner@example.invalid'',''self_managed'',now()+interval ''1 day'',%L,''bypass'',''TEST'',''must fail'')',
    expiry_org, owner_account
  ));
  perform pg_temp.refused(format(
    'insert into community_orgs.organisation_invitation_events(invitation_id,event_type,actor_id,reason) values(%L,''accepted'',%L,''bypass'')',
    cancel_invitation, owner_account
  ));
  reset role;

  perform pg_temp.refused(format(
    'update community_orgs.organisation_invitations set email=''changed@example.invalid'' where invitation_id=%L',
    accept_invitation
  ));
  perform pg_temp.refused(format(
    'delete from community_orgs.organisation_invitation_events where invitation_id=%L',
    accept_invitation
  ));
end
$$;

rollback;

select 'Email-bound invitation acceptance, cancellation, expiry and replay protection passed' as result;
