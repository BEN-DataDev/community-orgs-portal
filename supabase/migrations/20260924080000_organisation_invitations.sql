-- Phase 2, slice 2: email-bound organisation ownership invitations.
-- Delivery is deliberately outside this contract. The database owns the durable
-- invitation, verified-email acceptance and atomic role/stewardship handoff.

create type community_orgs.organisation_invitation_event_type as enum (
  'issued',
  'accepted',
  'cancelled',
  'expired'
);

create table community_orgs.organisation_invitations (
  invitation_id uuid primary key default gen_random_uuid(),
  -- Deliberately not an FK: invitation governance evidence survives a later
  -- organisation deletion, like organisation_stewardship_events.
  organisation_id uuid not null,
  email text not null,
  target_stewardship community_orgs.stewardship_state not null
    check (target_stewardship in ('self_managed', 'co_managed')),
  invited_at timestamptz not null default now(),
  expires_at timestamptz not null,
  invited_by uuid not null references auth.users(id) on delete restrict,
  reason text not null check (btrim(reason) <> '' and length(reason) <= 2000),
  approval_reference text not null
    check (btrim(approval_reference) <> '' and length(approval_reference) <= 500),
  note text not null check (btrim(note) <> '' and length(note) <= 4000),
  check (email = lower(btrim(email)) and email ~ '^[^[:space:]@]+@[^[:space:]@]+$'),
  check (expires_at > invited_at)
);

create table community_orgs.organisation_invitation_events (
  event_id bigint generated always as identity primary key,
  invitation_id uuid not null
    references community_orgs.organisation_invitations(invitation_id) on delete restrict,
  event_type community_orgs.organisation_invitation_event_type not null,
  occurred_at timestamptz not null default now(),
  actor_id uuid references auth.users(id) on delete restrict,
  reason text not null check (btrim(reason) <> '' and length(reason) <= 2000),
  unique (invitation_id, event_type)
);

-- Exactly one terminal outcome may ever be recorded for an invitation.
create unique index organisation_invitation_terminal_idx
  on community_orgs.organisation_invitation_events(invitation_id)
  where event_type <> 'issued';
create index organisation_invitations_org_time_idx
  on community_orgs.organisation_invitations(organisation_id, invited_at desc);
create index organisation_invitation_events_time_idx
  on community_orgs.organisation_invitation_events(invitation_id, occurred_at, event_id);

comment on table community_orgs.organisation_invitations is
  'Immutable, email-bound terms for an organisation owner handoff. Email delivery providers do not own this state.';
comment on table community_orgs.organisation_invitation_events is
  'Append-only issue and single terminal outcome history for organisation invitations.';

alter table community_orgs.organisation_invitations enable row level security;
alter table community_orgs.organisation_invitation_events enable row level security;
revoke all on community_orgs.organisation_invitations,
  community_orgs.organisation_invitation_events from public, anon, authenticated, service_role;
revoke all on sequence community_orgs.organisation_invitation_events_event_id_seq
  from public, anon, authenticated, service_role;

create trigger organisation_invitations_immutable
before update or delete on community_orgs.organisation_invitations
for each row execute function portal.reject_governance_history_mutation();

create trigger organisation_invitation_events_immutable
before update or delete on community_orgs.organisation_invitation_events
for each row execute function portal.reject_governance_history_mutation();

create function community_orgs.issue_organisation_invitation(
  p_organisation_id uuid,
  p_email text,
  p_target_stewardship text,
  p_reason text,
  p_approval_reference text,
  p_note text,
  p_expires_at timestamptz default (now() + interval '7 days')
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  current_state community_orgs.organisation_stewardship%rowtype;
  target community_orgs.stewardship_state;
  result uuid;
  stewardship_event bigint;
  normalised_email text := lower(btrim(p_email));
begin
  if community_orgs.is_portal_administrator() is distinct from true then
    raise exception 'Portal Administrator required' using errcode = '42501';
  end if;
  begin target := p_target_stewardship::community_orgs.stewardship_state;
  exception when invalid_text_representation then
    raise exception 'Invalid invitation stewardship outcome' using errcode = '22023';
  end;
  if target not in ('self_managed', 'co_managed')
     or normalised_email !~ '^[^[:space:]@]+@[^[:space:]@]+$'
     or length(normalised_email) > 320
     or nullif(btrim(p_reason), '') is null or length(p_reason) > 2000
     or nullif(btrim(p_approval_reference), '') is null or length(p_approval_reference) > 500
     or nullif(btrim(p_note), '') is null or length(p_note) > 4000
     or p_expires_at is null or p_expires_at <= now()
     or p_expires_at > now() + interval '30 days' then
    raise exception 'Valid email, outcome, expiry, reason, approval reference and note are required'
      using errcode = '22023';
  end if;

  perform 1 from community_orgs.organisations
  where org_id = p_organisation_id for update;
  if not found then raise exception 'Organisation not found' using errcode = 'P0002'; end if;
  select * into current_state from community_orgs.organisation_stewardship
  where organisation_id = p_organisation_id for update;
  if current_state.state <> 'unclaimed' then
    raise exception 'Only an unclaimed organisation can begin an owner handoff'
      using errcode = '23514';
  end if;
  if exists (
    select 1 from community_orgs.organisation_invitations i
    where i.organisation_id = p_organisation_id
      and not exists (
        select 1 from community_orgs.organisation_invitation_events e
        where e.invitation_id = i.invitation_id and e.event_type <> 'issued'
      )
  ) then
    raise exception 'This organisation already has a pending invitation' using errcode = '23505';
  end if;

  insert into community_orgs.organisation_invitations(
    organisation_id, email, target_stewardship, expires_at, invited_by,
    reason, approval_reference, note
  ) values (
    p_organisation_id, normalised_email, target, p_expires_at, auth.uid(),
    btrim(p_reason), btrim(p_approval_reference), btrim(p_note)
  ) returning invitation_id into result;
  insert into community_orgs.organisation_invitation_events(
    invitation_id, event_type, actor_id, reason
  ) values (result, 'issued', auth.uid(), btrim(p_reason));

  insert into community_orgs.organisation_stewardship_events(
    organisation_id, revision, previous_state, next_state, actor_id, reason,
    approval_reference, note, related_reference
  ) values (
    p_organisation_id, current_state.revision + 1, current_state.state,
    'invitation_pending', auth.uid(), btrim(p_reason), null, btrim(p_note), result::text
  ) returning event_id into stewardship_event;
  update community_orgs.organisation_stewardship
  set state = 'invitation_pending', revision = revision + 1,
      current_event_id = stewardship_event, updated_at = now()
  where organisation_id = p_organisation_id;
  return result;
end
$$;

create function community_orgs.finish_organisation_invitation_without_grant(
  p_invitation_id uuid,
  p_event_type community_orgs.organisation_invitation_event_type,
  p_actor_id uuid,
  p_reason text
) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  invitation community_orgs.organisation_invitations%rowtype;
  current_state community_orgs.organisation_stewardship%rowtype;
  stewardship_event bigint;
begin
  if p_event_type not in ('cancelled', 'expired') then
    raise exception 'Invalid invitation terminal event' using errcode = '22023';
  end if;
  select * into invitation from community_orgs.organisation_invitations
  where invitation_id = p_invitation_id for update;
  if not found then raise exception 'Invitation not found' using errcode = 'P0002'; end if;
  if exists (
    select 1 from community_orgs.organisation_invitation_events
    where invitation_id = p_invitation_id and event_type <> 'issued'
  ) then return false; end if;

  insert into community_orgs.organisation_invitation_events(
    invitation_id, event_type, actor_id, reason
  ) values (p_invitation_id, p_event_type, p_actor_id, btrim(p_reason));

  select * into current_state from community_orgs.organisation_stewardship
  where organisation_id = invitation.organisation_id for update;
  if current_state.state = 'invitation_pending' and exists (
    select 1 from community_orgs.organisation_stewardship_events e
    where e.event_id = current_state.current_event_id
      and e.related_reference = invitation.invitation_id::text
  ) then
    insert into community_orgs.organisation_stewardship_events(
      organisation_id, revision, previous_state, next_state, actor_id, reason,
      approval_reference, note, related_reference
    ) values (
      invitation.organisation_id, current_state.revision + 1, current_state.state,
      'unclaimed', p_actor_id, btrim(p_reason), null,
      case when p_event_type = 'expired'
        then 'The invitation expired without granting access.'
        else 'The invitation was cancelled without granting access.' end,
      invitation.invitation_id::text
    ) returning event_id into stewardship_event;
    update community_orgs.organisation_stewardship
    set state = 'unclaimed', revision = revision + 1,
        current_event_id = stewardship_event, updated_at = now()
    where organisation_id = invitation.organisation_id;
  end if;
  return true;
end
$$;

revoke all on function community_orgs.finish_organisation_invitation_without_grant(
  uuid,community_orgs.organisation_invitation_event_type,uuid,text
) from public, anon, authenticated, service_role;

create function community_orgs.cancel_organisation_invitation(
  p_invitation_id uuid,
  p_reason text
) returns boolean
language plpgsql security definer set search_path = '' as $$
declare invitation_expired boolean;
begin
  if community_orgs.is_portal_administrator() is distinct from true then
    raise exception 'Portal Administrator required' using errcode = '42501';
  end if;
  if nullif(btrim(p_reason), '') is null or length(p_reason) > 2000 then
    raise exception 'A cancellation reason is required' using errcode = '22023';
  end if;
  select expires_at <= now() into invitation_expired
  from community_orgs.organisation_invitations where invitation_id = p_invitation_id;
  return community_orgs.finish_organisation_invitation_without_grant(
    p_invitation_id,
    case when invitation_expired then 'expired'
      else 'cancelled' end::community_orgs.organisation_invitation_event_type,
    auth.uid(),
    case when invitation_expired then 'Invitation expired before cancellation: ' || p_reason
      else p_reason end
  );
end
$$;

create function community_orgs.accept_organisation_invitation(p_invitation_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  invitation community_orgs.organisation_invitations%rowtype;
  current_state community_orgs.organisation_stewardship%rowtype;
  account_email text;
  account_confirmed_at timestamptz;
  terminal community_orgs.organisation_invitation_event_type;
  owner_role uuid;
  assignment uuid;
  stewardship_event bigint;
begin
  if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean, false) then
    raise exception 'A registered account is required' using errcode = '42501';
  end if;
  select lower(btrim(email)), email_confirmed_at
    into account_email, account_confirmed_at
  from auth.users where id = auth.uid() and is_anonymous is not true;
  if not found or account_email is null or account_confirmed_at is null then
    raise exception 'A verified email address is required' using errcode = '42501';
  end if;

  select * into invitation from community_orgs.organisation_invitations
  where invitation_id = p_invitation_id for update;
  if not found then raise exception 'Invitation not found' using errcode = 'P0002'; end if;
  if account_email <> invitation.email then
    raise exception 'This invitation was issued to a different verified email address'
      using errcode = '42501';
  end if;
  select event_type into terminal
  from community_orgs.organisation_invitation_events
  where invitation_id = p_invitation_id and event_type <> 'issued';
  if found then return jsonb_build_object('status', terminal::text); end if;
  if invitation.expires_at <= now() then
    perform community_orgs.finish_organisation_invitation_without_grant(
      p_invitation_id, 'expired', auth.uid(), 'Invitation expired before acceptance'
    );
    return jsonb_build_object('status', 'expired');
  end if;

  select * into current_state from community_orgs.organisation_stewardship
  where organisation_id = invitation.organisation_id for update;
  if current_state.state is distinct from 'invitation_pending' or not exists (
    select 1 from community_orgs.organisation_stewardship_events e
    where e.event_id = current_state.current_event_id
      and e.related_reference = invitation.invitation_id::text
  ) then
    raise exception 'Invitation is no longer the current organisation handoff'
      using errcode = '40001';
  end if;
  select id into owner_role from community_orgs.roles
  where name = 'owner' and hierarchy_level = 4 order by id limit 1;
  if owner_role is null then raise exception 'Owner role is not configured' using errcode = '55000'; end if;

  insert into community_orgs.user_organisation_roles(
    user_id, organisation_id, role_id, granted_by, expires_at, is_active
  ) values (
    auth.uid(), invitation.organisation_id, owner_role, invitation.invited_by, null, true
  ) on conflict (user_id, organisation_id, role_id) do update set
    is_active = true, granted_by = excluded.granted_by, expires_at = null, updated_at = now()
  returning id into assignment;
  insert into community_orgs.role_audit_log(
    user_id, organisation_id, role_id, action, performed_by, reason
  ) values (
    auth.uid(), invitation.organisation_id, owner_role, 'granted', invitation.invited_by,
    'Accepted email-bound organisation invitation ' || invitation.invitation_id::text
  );
  insert into community_orgs.organisation_invitation_events(
    invitation_id, event_type, actor_id, reason
  ) values (
    invitation.invitation_id, 'accepted', auth.uid(), 'Verified invitee accepted ownership'
  );
  insert into community_orgs.organisation_stewardship_events(
    organisation_id, revision, previous_state, next_state, actor_id, reason,
    approval_reference, note, related_reference
  ) values (
    invitation.organisation_id, current_state.revision + 1, current_state.state,
    invitation.target_stewardship, auth.uid(), invitation.reason,
    invitation.approval_reference, invitation.note, invitation.invitation_id::text
  ) returning event_id into stewardship_event;
  update community_orgs.organisation_stewardship
  set state = invitation.target_stewardship, revision = revision + 1,
      current_event_id = stewardship_event, updated_at = now()
  where organisation_id = invitation.organisation_id;
  return jsonb_build_object(
    'status', 'accepted', 'organisationId', invitation.organisation_id,
    'assignmentId', assignment, 'stewardship', invitation.target_stewardship
  );
end
$$;

create function community_orgs.organisation_invitation(p_invitation_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare invitation community_orgs.organisation_invitations%rowtype;
declare terminal community_orgs.organisation_invitation_event_type;
declare account_email text;
begin
  select * into invitation from community_orgs.organisation_invitations
  where invitation_id = p_invitation_id;
  if not found then raise exception 'Invitation not found' using errcode = 'P0002'; end if;
  select lower(btrim(email)) into account_email from auth.users
  where id = auth.uid() and is_anonymous is not true and email_confirmed_at is not null;
  if account_email is distinct from invitation.email
     and community_orgs.is_portal_administrator() is distinct from true then
    raise exception 'Invitation access denied' using errcode = '42501';
  end if;
  select event_type into terminal from community_orgs.organisation_invitation_events
  where invitation_id = p_invitation_id and event_type <> 'issued';
  if terminal is null and invitation.expires_at <= now() then
    perform community_orgs.finish_organisation_invitation_without_grant(
      p_invitation_id, 'expired', auth.uid(), 'Invitation expired before it was viewed'
    );
    terminal := 'expired';
  end if;
  return jsonb_build_object(
    'id', invitation.invitation_id,
    'organisationId', invitation.organisation_id,
    'organisationName', (select entity_name from community_orgs.organisations
      where org_id = invitation.organisation_id),
    'email', invitation.email,
    'targetStewardship', invitation.target_stewardship,
    'note', invitation.note,
    'expiresAt', invitation.expires_at,
    'status', coalesce(terminal::text, 'pending')
  );
end
$$;

-- Extend the existing private roster with pending/history invitation data. This
-- remains one RPC so no invitation email is exposed through a table policy.
create or replace function community_orgs.organisation_role_assignments(p_organisation_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_level integer; v_name text; v_can_invite boolean; expired_invitation uuid;
begin
 perform community_orgs.require_role_management_session();
 if not community_orgs.user_has_permission(auth.uid(),p_organisation_id,'can_manage_members') then
   raise exception 'Organisation role management access required' using errcode='42501';
 end if;
 select entity_name into v_name from community_orgs.organisations where org_id=p_organisation_id;
 if not found then raise exception 'unknown organisation'; end if;
 for expired_invitation in
   select i.invitation_id from community_orgs.organisation_invitations i
   where i.organisation_id=p_organisation_id and i.expires_at<=now()
     and not exists(select 1 from community_orgs.organisation_invitation_events e
       where e.invitation_id=i.invitation_id and e.event_type<>'issued')
 loop
   perform community_orgs.finish_organisation_invitation_without_grant(
     expired_invitation,'expired',auth.uid(),'Invitation expiry recorded during access review'
   );
 end loop;
 v_level:=community_orgs.user_max_role_level(auth.uid(),p_organisation_id);
 v_can_invite:=community_orgs.is_portal_administrator() and exists(
   select 1 from community_orgs.organisation_stewardship
   where organisation_id=p_organisation_id and state='unclaimed'
 );
 return jsonb_build_object('name',v_name,'level',v_level,'canInvite',v_can_invite,
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
 where u.organisation_id=p_organisation_id),'[]'::jsonb),
 'invitations',coalesce((select jsonb_agg(jsonb_build_object(
   'id',i.invitation_id,'email',i.email,'targetStewardship',i.target_stewardship,
   'invitedAt',i.invited_at,'expiresAt',i.expires_at,
   'canCancel',community_orgs.is_portal_administrator() and not exists(
     select 1 from community_orgs.organisation_invitation_events terminal
     where terminal.invitation_id=i.invitation_id and terminal.event_type<>'issued'
   ),
   'status',coalesce((select e.event_type::text from community_orgs.organisation_invitation_events e
     where e.invitation_id=i.invitation_id and e.event_type<>'issued'),
     case when i.expires_at<=now() then 'expired' else 'pending' end)
 ) order by i.invited_at desc)
 from community_orgs.organisation_invitations i
 where i.organisation_id=p_organisation_id),'[]'::jsonb));
end $$;

revoke all on function community_orgs.issue_organisation_invitation(uuid,text,text,text,text,text,timestamptz),
  community_orgs.cancel_organisation_invitation(uuid,text),
  community_orgs.accept_organisation_invitation(uuid),
  community_orgs.organisation_invitation(uuid) from public, anon, service_role;
grant execute on function community_orgs.issue_organisation_invitation(uuid,text,text,text,text,text,timestamptz),
  community_orgs.cancel_organisation_invitation(uuid,text),
  community_orgs.accept_organisation_invitation(uuid),
  community_orgs.organisation_invitation(uuid) to authenticated;
