-- Phase 2, slice 1: explicit portal capabilities and organisation stewardship.
-- A database is one portal, so appointments deliberately do not repeat portal_id.

create type portal.capability as enum ('portal_administrator', 'data_steward');
create type portal.appointment_event_type as enum ('issued', 'revoked');

create table portal.capability_appointments (
  appointment_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  capability portal.capability not null,
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  appointed_at timestamptz not null default now(),
  appointed_by uuid references auth.users(id) on delete restrict,
  reason text not null check (btrim(reason) <> '' and length(reason) <= 2000),
  approval_reference text not null
    check (btrim(approval_reference) <> '' and length(approval_reference) <= 500),
  origin text not null default 'application'
    check (origin in ('application', 'bootstrap', 'legacy_platform_admin', 'legacy_ingestion_operator')),
  check (expires_at is null or expires_at > starts_at),
  check (appointed_by is not null or origin <> 'application')
);

create table portal.capability_appointment_events (
  event_id bigint generated always as identity primary key,
  appointment_id uuid not null
    references portal.capability_appointments(appointment_id) on delete restrict,
  event_type portal.appointment_event_type not null,
  occurred_at timestamptz not null default now(),
  actor_id uuid references auth.users(id) on delete restrict,
  reason text not null check (btrim(reason) <> '' and length(reason) <= 2000),
  approval_reference text not null
    check (btrim(approval_reference) <> '' and length(approval_reference) <= 500),
  unique (appointment_id, event_type)
);

create index capability_appointments_current_idx
  on portal.capability_appointments(user_id, capability, starts_at, expires_at);
create index capability_appointment_events_time_idx
  on portal.capability_appointment_events(appointment_id, occurred_at, event_id);

comment on table portal.capability_appointments is
  'Immutable Portal Administrator and Data Steward appointment terms for this isolated portal.';
comment on table portal.capability_appointment_events is
  'Append-only issue and revocation evidence. Current authority is derived, never stored in a mutable flag.';

alter table portal.capability_appointments enable row level security;
alter table portal.capability_appointment_events enable row level security;
revoke all on portal.capability_appointments, portal.capability_appointment_events
  from public, anon, authenticated, service_role;
revoke all on sequence portal.capability_appointment_events_event_id_seq
  from public, anon, authenticated, service_role;

create function portal.reject_governance_history_mutation() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'Portal governance history is append-only' using errcode = '55000';
end
$$;

create trigger capability_appointments_immutable
before update or delete on portal.capability_appointments
for each row execute function portal.reject_governance_history_mutation();

create trigger capability_appointment_events_immutable
before update or delete on portal.capability_appointment_events
for each row execute function portal.reject_governance_history_mutation();

create function portal.record_capability_appointment_issue() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into portal.capability_appointment_events(
    appointment_id, event_type, occurred_at, actor_id, reason, approval_reference
  ) values (
    new.appointment_id, 'issued', new.appointed_at, new.appointed_by,
    new.reason, new.approval_reference
  );
  return new;
end
$$;

create trigger capability_appointment_issue_event
after insert on portal.capability_appointments
for each row execute function portal.record_capability_appointment_issue();

create function portal.has_current_capability(p_capability portal.capability) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null
    and coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false
    and (not community_orgs.user_has_verified_mfa()
      or coalesce(auth.jwt()->>'aal' = 'aal2', false))
    and exists (
      select 1
      from portal.capability_appointments a
      where a.user_id = auth.uid()
        and a.capability = p_capability
        and a.starts_at <= now()
        and (a.expires_at is null or a.expires_at > now())
        and not exists (
          select 1 from portal.capability_appointment_events e
          where e.appointment_id = a.appointment_id and e.event_type = 'revoked'
        )
    )
$$;

create function community_orgs.is_portal_administrator() returns boolean
language sql stable security definer set search_path = '' as $$
  select portal.has_current_capability('portal_administrator')
$$;

create function community_orgs.is_data_steward() returns boolean
language sql stable security definer set search_path = '' as $$
  select portal.has_current_capability('data_steward')
$$;

-- Keep deployed callers working while removing the old implicit union of portal
-- governance, ingestion and organisation ownership.
create or replace function community_orgs.is_platform_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select community_orgs.is_portal_administrator()
$$;

create or replace function community_orgs.is_ingestion_operator() returns boolean
language sql stable security definer set search_path = '' as $$
  select community_orgs.is_data_steward()
$$;

revoke all on function portal.has_current_capability(portal.capability) from public;
revoke all on function community_orgs.is_portal_administrator(),
  community_orgs.is_data_steward(), community_orgs.is_platform_admin(),
  community_orgs.is_ingestion_operator() from public, anon;
grant execute on function community_orgs.is_portal_administrator(),
  community_orgs.is_data_steward(), community_orgs.is_platform_admin(),
  community_orgs.is_ingestion_operator() to authenticated;

-- Convert every controlled legacy appointment into explicit retained evidence.
insert into portal.capability_appointments(
  user_id, capability, starts_at, appointed_at, appointed_by, reason,
  approval_reference, origin
)
select user_id, 'portal_administrator', granted_at, granted_at, null,
  reason, 'legacy-platform-administrator-migration', 'legacy_platform_admin'
from platform_access.administrators;

insert into portal.capability_appointments(
  user_id, capability, starts_at, appointed_at, appointed_by, reason,
  approval_reference, origin
)
select user_id, 'data_steward', granted_at, granted_at, null,
  'Migrated legacy ingestion operator appointment',
  'legacy-ingestion-operator-migration', 'legacy_ingestion_operator'
from ingestion.operators;

-- Temporary database-operation bridges retain old runbooks and test fixtures.
-- Authority still comes only from the new appointment/event model.
create function portal.mirror_legacy_platform_administrator() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    insert into portal.capability_appointments(
      user_id, capability, starts_at, appointed_at, appointed_by, reason,
      approval_reference, origin
    ) values (
      new.user_id, 'portal_administrator', new.granted_at, new.granted_at, null,
      new.reason, 'legacy-platform-administrator-operation', 'legacy_platform_admin'
    );
    return new;
  end if;
  insert into portal.capability_appointment_events(
    appointment_id, event_type, actor_id, reason, approval_reference
  )
  select a.appointment_id, 'revoked', null,
    'Legacy platform administrator appointment removed',
    'legacy-platform-administrator-operation'
  from portal.capability_appointments a
  where a.user_id = old.user_id and a.capability = 'portal_administrator'
    and a.origin = 'legacy_platform_admin'
    and not exists (
      select 1 from portal.capability_appointment_events e
      where e.appointment_id = a.appointment_id and e.event_type = 'revoked'
    );
  return old;
end
$$;

create trigger mirror_legacy_platform_administrator
after insert or delete on platform_access.administrators
for each row execute function portal.mirror_legacy_platform_administrator();

create function portal.mirror_legacy_ingestion_operator() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    insert into portal.capability_appointments(
      user_id, capability, starts_at, appointed_at, appointed_by, reason,
      approval_reference, origin
    ) values (
      new.user_id, 'data_steward', new.granted_at, new.granted_at, null,
      'Legacy ingestion operator appointment',
      'legacy-ingestion-operator-operation', 'legacy_ingestion_operator'
    );
    return new;
  end if;
  insert into portal.capability_appointment_events(
    appointment_id, event_type, actor_id, reason, approval_reference
  )
  select a.appointment_id, 'revoked', null,
    'Legacy ingestion operator appointment removed',
    'legacy-ingestion-operator-operation'
  from portal.capability_appointments a
  where a.user_id = old.user_id and a.capability = 'data_steward'
    and a.origin = 'legacy_ingestion_operator'
    and not exists (
      select 1 from portal.capability_appointment_events e
      where e.appointment_id = a.appointment_id and e.event_type = 'revoked'
    );
  return old;
end
$$;

create trigger mirror_legacy_ingestion_operator
after insert or delete on ingestion.operators
for each row execute function portal.mirror_legacy_ingestion_operator();

create function community_orgs.appoint_portal_capability(
  p_user_id uuid,
  p_capability text,
  p_reason text,
  p_approval_reference text,
  p_starts_at timestamptz default now(),
  p_expires_at timestamptz default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  target_capability portal.capability;
  result uuid;
begin
  if community_orgs.is_portal_administrator() is distinct from true then
    raise exception 'Portal Administrator required' using errcode = '42501';
  end if;
  begin target_capability := p_capability::portal.capability;
  exception when invalid_text_representation then
    raise exception 'Invalid portal capability' using errcode = '22023';
  end;
  if nullif(btrim(p_reason), '') is null or length(p_reason) > 2000
     or nullif(btrim(p_approval_reference), '') is null
     or length(p_approval_reference) > 500
     or p_starts_at is null
     or (p_expires_at is not null and p_expires_at <= greatest(p_starts_at, now())) then
    raise exception 'Valid appointment terms, reason and approval reference are required'
      using errcode = '22023';
  end if;
  if not exists (
    select 1 from auth.users where id = p_user_id and is_anonymous is not true
  ) then
    raise exception 'Target must be a registered account' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':' || target_capability::text, 0));
  if exists (
    select 1 from portal.capability_appointments a
    where a.user_id = p_user_id and a.capability = target_capability
      and a.starts_at < coalesce(p_expires_at, 'infinity'::timestamptz)
      and p_starts_at < coalesce(a.expires_at, 'infinity'::timestamptz)
      and not exists (
        select 1 from portal.capability_appointment_events e
        where e.appointment_id = a.appointment_id and e.event_type = 'revoked'
      )
  ) then
    raise exception 'Account already has an overlapping appointment for this capability'
      using errcode = '23505';
  end if;
  insert into portal.capability_appointments(
    user_id, capability, starts_at, expires_at, appointed_by, reason,
    approval_reference
  ) values (
    p_user_id, target_capability, p_starts_at, p_expires_at, auth.uid(),
    btrim(p_reason), btrim(p_approval_reference)
  ) returning appointment_id into result;
  return result;
end
$$;

create function community_orgs.revoke_portal_capability(
  p_appointment_id uuid,
  p_reason text,
  p_approval_reference text
) returns boolean
language plpgsql security definer set search_path = '' as $$
declare target portal.capability_appointments%rowtype;
begin
  if community_orgs.is_portal_administrator() is distinct from true then
    raise exception 'Portal Administrator required' using errcode = '42501';
  end if;
  if nullif(btrim(p_reason), '') is null or length(p_reason) > 2000
     or nullif(btrim(p_approval_reference), '') is null
     or length(p_approval_reference) > 500 then
    raise exception 'A reason and approval reference are required' using errcode = '22023';
  end if;
  select * into target from portal.capability_appointments
  where appointment_id = p_appointment_id for update;
  if not found then raise exception 'Appointment not found' using errcode = 'P0002'; end if;
  if exists (
    select 1 from portal.capability_appointment_events
    where appointment_id = target.appointment_id and event_type = 'revoked'
  ) then return false; end if;
  if target.capability = 'portal_administrator'
     and target.starts_at <= now()
     and (target.expires_at is null or target.expires_at > now())
     and not exists (
       select 1 from portal.capability_appointments a
       where a.capability = 'portal_administrator'
         and a.appointment_id <> target.appointment_id
         and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now())
         and not exists (
           select 1 from portal.capability_appointment_events e
           where e.appointment_id = a.appointment_id and e.event_type = 'revoked'
         )
     ) then
    raise exception 'Appoint another current Portal Administrator before revoking the last one'
      using errcode = '23514';
  end if;
  insert into portal.capability_appointment_events(
    appointment_id, event_type, actor_id, reason, approval_reference
  ) values (
    target.appointment_id, 'revoked', auth.uid(), btrim(p_reason),
    btrim(p_approval_reference)
  );
  return true;
end
$$;

revoke all on function community_orgs.appoint_portal_capability(uuid,text,text,text,timestamptz,timestamptz),
  community_orgs.revoke_portal_capability(uuid,text,text) from public, anon, service_role;
grant execute on function community_orgs.appoint_portal_capability(uuid,text,text,text,timestamptz,timestamptz),
  community_orgs.revoke_portal_capability(uuid,text,text) to authenticated;

-- Stewardship is organisation governance evidence, not an organisation role.
create type community_orgs.stewardship_state as enum (
  'unclaimed',
  'invitation_pending',
  'self_managed',
  'portal_managed',
  'co_managed',
  'suspended'
);

create table community_orgs.organisation_stewardship_events (
  event_id bigint generated always as identity primary key,
  organisation_id uuid not null,
  revision bigint not null check (revision > 0),
  previous_state community_orgs.stewardship_state,
  next_state community_orgs.stewardship_state not null,
  effective_at timestamptz not null default now(),
  occurred_at timestamptz not null default now(),
  actor_id uuid references auth.users(id) on delete restrict,
  reason text not null check (btrim(reason) <> '' and length(reason) <= 2000),
  approval_reference text,
  note text not null check (btrim(note) <> '' and length(note) <= 4000),
  related_reference text,
  unique (organisation_id, revision),
  check (approval_reference is null or (btrim(approval_reference) <> '' and length(approval_reference) <= 500)),
  check (related_reference is null or (btrim(related_reference) <> '' and length(related_reference) <= 500)),
  check ((revision = 1 and previous_state is null)
    or (revision > 1 and previous_state is not null))
);

create table community_orgs.organisation_stewardship (
  organisation_id uuid primary key
    references community_orgs.organisations(org_id) on delete cascade,
  state community_orgs.stewardship_state not null,
  revision bigint not null check (revision > 0),
  current_event_id bigint not null unique
    references community_orgs.organisation_stewardship_events(event_id) on delete restrict,
  updated_at timestamptz not null
);

create index organisation_stewardship_events_time_idx
  on community_orgs.organisation_stewardship_events(organisation_id, occurred_at, event_id);

comment on table community_orgs.organisation_stewardship is
  'Current stewardship projection. It is changed only with its append-only event in one transaction.';
comment on table community_orgs.organisation_stewardship_events is
  'Append-only organisation stewardship decisions retained even if the organisation is later removed.';

alter table community_orgs.organisation_stewardship enable row level security;
alter table community_orgs.organisation_stewardship_events enable row level security;
revoke all on community_orgs.organisation_stewardship,
  community_orgs.organisation_stewardship_events from public, anon, authenticated, service_role;
revoke all on sequence community_orgs.organisation_stewardship_events_event_id_seq
  from public, anon, authenticated, service_role;

create trigger organisation_stewardship_events_immutable
before update or delete on community_orgs.organisation_stewardship_events
for each row execute function portal.reject_governance_history_mutation();

-- Backfill owner-governed records as self-managed; imported/no-owner records
-- remain unclaimed. No role or ownership is created by this migration.
with classified as (
  select o.org_id,
    case when exists (
      select 1 from community_orgs.user_organisation_roles u
      join community_orgs.roles r on r.id = u.role_id
      where u.organisation_id = o.org_id and u.is_active
        and (u.expires_at is null or u.expires_at > now())
        and r.hierarchy_level = 4
    ) then 'self_managed'::community_orgs.stewardship_state
      else 'unclaimed'::community_orgs.stewardship_state end as state
  from community_orgs.organisations o
), inserted as (
  insert into community_orgs.organisation_stewardship_events(
    organisation_id, revision, previous_state, next_state, actor_id, reason,
    approval_reference, note
  )
  select org_id, 1, null, state, null,
    'Phase 2 stewardship baseline',
    case when state = 'self_managed' then 'existing-owner-assignment' end,
    case when state = 'self_managed'
      then 'Classified from an existing effective owner assignment.'
      else 'No effective owner existed at the stewardship baseline.' end
  from classified
  returning event_id, organisation_id, next_state, occurred_at
)
insert into community_orgs.organisation_stewardship(
  organisation_id, state, revision, current_event_id, updated_at
)
select organisation_id, next_state, 1, event_id, occurred_at from inserted;

create function community_orgs.initialise_organisation_stewardship() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  initial_state community_orgs.stewardship_state;
  event bigint;
  imported boolean;
begin
  select exists(select 1 from ingestion.creation_targets where org_id = new.org_id)
    into imported;
  initial_state := case when auth.uid() is not null and not imported
    then 'self_managed'::community_orgs.stewardship_state
    else 'unclaimed'::community_orgs.stewardship_state end;
  insert into community_orgs.organisation_stewardship_events(
    organisation_id, revision, previous_state, next_state, actor_id, reason,
    approval_reference, note
  ) values (
    new.org_id, 1, null, initial_state,
    case when imported then null else auth.uid() end,
    case when imported then 'Imported publication created an unclaimed organisation'
      when auth.uid() is not null then 'Registered account created the organisation'
      else 'Database operation created an unclaimed organisation' end,
    case when initial_state = 'self_managed' then 'direct-organisation-creation' end,
    case when initial_state = 'self_managed'
      then 'The creator received the owner role in the same transaction.'
      else 'No organisation representative has accepted stewardship.' end
  ) returning event_id into event;
  insert into community_orgs.organisation_stewardship(
    organisation_id, state, revision, current_event_id, updated_at
  ) values (new.org_id, initial_state, 1, event, now());
  return new;
end
$$;

create trigger initialise_organisation_stewardship
after insert on community_orgs.organisations
for each row execute function community_orgs.initialise_organisation_stewardship();

create function community_orgs.portal_administrator_can_edit_organisation(p_organisation_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select community_orgs.is_portal_administrator() and exists (
    select 1
    from community_orgs.organisation_stewardship s
    join community_orgs.organisation_stewardship_events e
      on e.event_id = s.current_event_id
    where s.organisation_id = p_organisation_id
      and (
        s.state in ('unclaimed', 'invitation_pending')
        or (s.state in ('portal_managed', 'co_managed')
          and nullif(btrim(e.approval_reference), '') is not null
          and e.effective_at <= now())
      )
  )
$$;

create or replace function community_orgs.user_has_permission(
  p_user_id uuid, p_organisation_id uuid, p_permission text
) returns boolean language sql stable security definer set search_path = '' as $$
  select (
    p_user_id = auth.uid()
    and community_orgs.portal_administrator_can_edit_organisation(p_organisation_id)
  ) or exists (
    select 1
    from community_orgs.user_organisation_roles u
    join community_orgs.roles r on r.id = u.role_id
    where u.user_id = p_user_id and u.organisation_id = p_organisation_id
      and u.is_active and (u.expires_at is null or u.expires_at > now())
      and r.permissions->>p_permission = 'true'
  )
$$;

create or replace function community_orgs.user_max_role_level(
  p_user_id uuid, p_organisation_id uuid
) returns integer language sql stable security definer set search_path = '' as $$
  select case when p_user_id = auth.uid()
      and community_orgs.portal_administrator_can_edit_organisation(p_organisation_id)
    then 4 else coalesce((
      select max(r.hierarchy_level)
      from community_orgs.user_organisation_roles u
      join community_orgs.roles r on r.id = u.role_id
      where u.user_id = p_user_id and u.organisation_id = p_organisation_id
        and u.is_active and (u.expires_at is null or u.expires_at > now())
    ), 0) end
$$;

create or replace function community_orgs.can_view_org(p_org_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from community_orgs.organisations o
    where o.org_id = p_org_id and (
      o.is_public
      or community_orgs.portal_administrator_can_edit_organisation(o.org_id)
      or exists (
        select 1 from community_orgs.user_organisation_roles u
        where u.organisation_id = o.org_id and u.user_id = auth.uid()
          and u.is_active and (u.expires_at is null or u.expires_at > now())
      )
    )
  )
$$;

drop policy if exists "platform admin read" on community_orgs.organisations;
drop policy if exists "platform admin delete" on community_orgs.organisations;
create policy "stewardship portal administrator read"
  on community_orgs.organisations for select to authenticated
  using ((select community_orgs.portal_administrator_can_edit_organisation(org_id)));
create policy "stewardship portal administrator delete"
  on community_orgs.organisations for delete to authenticated
  using ((select community_orgs.portal_administrator_can_edit_organisation(org_id)));

create function community_orgs.set_organisation_stewardship(
  p_organisation_id uuid,
  p_next_state text,
  p_reason text,
  p_approval_reference text,
  p_note text,
  p_related_reference text default null,
  p_expected_revision bigint default null
) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  current_state community_orgs.organisation_stewardship%rowtype;
  target community_orgs.stewardship_state;
  event bigint;
begin
  if community_orgs.is_portal_administrator() is distinct from true then
    raise exception 'Portal Administrator required' using errcode = '42501';
  end if;
  begin target := p_next_state::community_orgs.stewardship_state;
  exception when invalid_text_representation then
    raise exception 'Invalid stewardship state' using errcode = '22023';
  end;
  if nullif(btrim(p_reason), '') is null or length(p_reason) > 2000
     or nullif(btrim(p_note), '') is null or length(p_note) > 4000
     or (target in ('self_managed', 'portal_managed', 'co_managed')
       and nullif(btrim(p_approval_reference), '') is null)
     or length(p_approval_reference) > 500
     or length(p_related_reference) > 500 then
    raise exception 'Valid reason, note and required approval reference are required'
      using errcode = '22023';
  end if;
  select * into current_state from community_orgs.organisation_stewardship
  where organisation_id = p_organisation_id for update;
  if not found then raise exception 'Organisation not found' using errcode = 'P0002'; end if;
  if p_expected_revision is not null and current_state.revision <> p_expected_revision then
    raise exception 'Stewardship changed; reload before saving' using errcode = '40001';
  end if;
  if current_state.state = target then return current_state.current_event_id; end if;
  -- Invitation expiry/cancellation may return to unclaimed, but can never
  -- manufacture continuing portal-management authority.
  if current_state.state = 'invitation_pending' and target = 'portal_managed' then
    raise exception 'An invitation cannot create portal-managed stewardship'
      using errcode = '22023';
  end if;
  insert into community_orgs.organisation_stewardship_events(
    organisation_id, revision, previous_state, next_state, actor_id, reason,
    approval_reference, note, related_reference
  ) values (
    p_organisation_id, current_state.revision + 1, current_state.state, target,
    auth.uid(), btrim(p_reason), nullif(btrim(p_approval_reference), ''),
    btrim(p_note), nullif(btrim(p_related_reference), '')
  ) returning event_id into event;
  update community_orgs.organisation_stewardship
  set state = target, revision = revision + 1, current_event_id = event,
      updated_at = now()
  where organisation_id = p_organisation_id;
  return event;
end
$$;

revoke all on function community_orgs.portal_administrator_can_edit_organisation(uuid),
  community_orgs.set_organisation_stewardship(uuid,text,text,text,text,text,bigint)
  from public, anon, service_role;
grant execute on function community_orgs.portal_administrator_can_edit_organisation(uuid),
  community_orgs.set_organisation_stewardship(uuid,text,text,text,text,text,bigint)
  to authenticated;
