-- One database represents exactly one portal. Keep the identity in a private
-- schema and expose only the deliberately public display fields through an RPC.
create schema if not exists portal;
revoke all on schema portal from public, anon, authenticated, service_role;

create type portal.lifecycle_state as enum (
  'planned',
  'provisioned',
  'scope_configured',
  'seeding',
  'seed_review',
  'initial_release_approved',
  'operational',
  'suspended',
  'retired'
);

create table portal.configuration (
  singleton boolean primary key default true check (singleton),
  portal_id uuid not null unique,
  portal_key text not null unique check (portal_key ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  display_name text not null check (btrim(display_name) <> ''),
  short_name text not null check (btrim(short_name) <> ''),
  sponsor_name text not null check (btrim(sponsor_name) <> ''),
  sponsor_url text check (sponsor_url is null or sponsor_url ~ '^https://'),
  contact_email text,
  logo_url text check (logo_url is null or logo_url ~ '^https://'),
  lifecycle_state portal.lifecycle_state not null default 'planned',
  scope_reference text,
  configuration_revision bigint not null default 1 check (configuration_revision > 0),
  established_at timestamptz not null default now(),
  established_by uuid references auth.users(id) on delete restrict,
  establishment_reason text not null check (btrim(establishment_reason) <> ''),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete restrict
);

comment on table portal.configuration is
  'Singleton identity and current display/lifecycle configuration for this isolated portal database.';
comment on column portal.configuration.portal_key is
  'Stable deployment-manifest key; unlike the display name it must never be repurposed.';
comment on column portal.configuration.scope_reference is
  'Establishment reference proving scope was configured; PEG02 will replace this bridge with a scope revision FK.';

create table portal.lifecycle_events (
  event_id bigint generated always as identity primary key,
  portal_id uuid not null references portal.configuration(portal_id) on delete restrict,
  previous_state portal.lifecycle_state,
  next_state portal.lifecycle_state not null,
  occurred_at timestamptz not null default now(),
  actor_id uuid references auth.users(id) on delete restrict,
  reason text not null check (btrim(reason) <> ''),
  reference text,
  configuration_revision bigint not null check (configuration_revision > 0)
);

create index lifecycle_events_portal_time_idx
  on portal.lifecycle_events(portal_id, occurred_at, event_id);

alter table portal.configuration enable row level security;
alter table portal.lifecycle_events enable row level security;
revoke all on portal.configuration, portal.lifecycle_events
  from public, anon, authenticated, service_role;
revoke all on sequence portal.lifecycle_events_event_id_seq
  from public, anon, authenticated, service_role;

create function portal.preserve_identity() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.singleton is distinct from old.singleton
     or new.portal_id is distinct from old.portal_id
     or new.portal_key is distinct from old.portal_key
     or new.established_at is distinct from old.established_at
     or new.established_by is distinct from old.established_by
     or new.establishment_reason is distinct from old.establishment_reason then
    raise exception 'Portal establishment identity is immutable' using errcode = '55000';
  end if;
  return new;
end
$$;

create trigger portal_identity_immutable
before update on portal.configuration
for each row execute function portal.preserve_identity();

create function portal.reject_lifecycle_event_mutation() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'Portal lifecycle events are append-only' using errcode = '55000';
end
$$;

create trigger lifecycle_events_immutable
before update or delete on portal.lifecycle_events
for each row execute function portal.reject_lifecycle_event_mutation();

-- The initial planned event is inseparable from establishment. Provisioning is
-- intentionally a direct database operation: no web or service-role API can
-- create or replace a portal identity.
create function portal.record_establishment() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into portal.lifecycle_events(
    portal_id, previous_state, next_state, occurred_at, actor_id, reason,
    reference, configuration_revision
  ) values (
    new.portal_id, null, new.lifecycle_state, new.established_at,
    new.established_by, new.establishment_reason, 'portal_establishment',
    new.configuration_revision
  );
  return new;
end
$$;

create trigger portal_establishment_event
after insert on portal.configuration
for each row execute function portal.record_establishment();

create function community_orgs.get_portal_identity()
returns table (
  portal_id uuid,
  portal_key text,
  display_name text,
  short_name text,
  sponsor_name text,
  sponsor_url text,
  logo_url text,
  lifecycle_state text,
  configuration_revision bigint
)
language sql stable security definer set search_path = '' as $$
  select c.portal_id, c.portal_key, c.display_name, c.short_name,
         c.sponsor_name, c.sponsor_url, c.logo_url,
         c.lifecycle_state::text, c.configuration_revision
  from portal.configuration c
  where c.singleton
$$;

revoke all on function community_orgs.get_portal_identity()
  from public, anon, authenticated, service_role;
grant execute on function community_orgs.get_portal_identity() to anon, authenticated, service_role;

create function community_orgs.update_portal_configuration(
  p_display_name text,
  p_short_name text,
  p_sponsor_name text,
  p_sponsor_url text default null,
  p_logo_url text default null,
  p_expected_revision bigint default null
) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  next_revision bigint;
begin
  if community_orgs.is_platform_admin() is distinct from true then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  if nullif(btrim(p_display_name), '') is null
     or nullif(btrim(p_short_name), '') is null
     or nullif(btrim(p_sponsor_name), '') is null then
    raise exception 'Portal and sponsor names are required' using errcode = '22023';
  end if;

  update portal.configuration
  set display_name = btrim(p_display_name),
      short_name = btrim(p_short_name),
      sponsor_name = btrim(p_sponsor_name),
      sponsor_url = nullif(btrim(p_sponsor_url), ''),
      logo_url = nullif(btrim(p_logo_url), ''),
      configuration_revision = configuration_revision + 1,
      updated_at = now(),
      updated_by = auth.uid()
  where singleton
    and (p_expected_revision is null or configuration_revision = p_expected_revision)
  returning configuration_revision into next_revision;

  if next_revision is null then
    if not exists (select 1 from portal.configuration) then
      raise exception 'Portal identity is not configured' using errcode = 'P0002';
    end if;
    raise exception 'Portal configuration changed; reload before saving' using errcode = '40001';
  end if;
  return next_revision;
end
$$;

create function community_orgs.transition_portal_lifecycle(
  p_next_state text,
  p_reason text,
  p_reference text default null,
  p_expected_revision bigint default null
) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  current_config portal.configuration%rowtype;
  target portal.lifecycle_state;
  next_revision bigint;
begin
  if community_orgs.is_platform_admin() is distinct from true then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception 'A lifecycle transition reason is required' using errcode = '22023';
  end if;
  begin
    target := p_next_state::portal.lifecycle_state;
  exception when invalid_text_representation then
    raise exception 'Invalid portal lifecycle state' using errcode = '22023';
  end;

  select * into current_config from portal.configuration where singleton for update;
  if not found then
    raise exception 'Portal identity is not configured' using errcode = 'P0002';
  end if;
  if p_expected_revision is not null
     and current_config.configuration_revision <> p_expected_revision then
    raise exception 'Portal configuration changed; reload before saving' using errcode = '40001';
  end if;
  if target = current_config.lifecycle_state then
    return current_config.configuration_revision;
  end if;
  if not (
    (current_config.lifecycle_state = 'planned' and target = 'provisioned') or
    (current_config.lifecycle_state = 'provisioned' and target = 'scope_configured') or
    (current_config.lifecycle_state = 'scope_configured' and target = 'seeding') or
    (current_config.lifecycle_state = 'seeding' and target = 'seed_review') or
    (current_config.lifecycle_state = 'seed_review' and target = 'initial_release_approved') or
    (current_config.lifecycle_state = 'initial_release_approved' and target = 'operational') or
    (current_config.lifecycle_state = 'operational' and target = 'suspended') or
    (current_config.lifecycle_state = 'suspended' and target in ('operational', 'retired'))
  ) then
    raise exception 'Invalid portal lifecycle transition: % to %',
      current_config.lifecycle_state, target using errcode = '22023';
  end if;
  if target = 'scope_configured' and nullif(btrim(p_reference), '') is null then
    raise exception 'A scope configuration reference is required' using errcode = '22023';
  end if;

  next_revision := current_config.configuration_revision + 1;
  update portal.configuration
  set lifecycle_state = target,
      scope_reference = case when target = 'scope_configured'
        then btrim(p_reference) else scope_reference end,
      configuration_revision = next_revision,
      updated_at = now(),
      updated_by = auth.uid()
  where singleton;

  insert into portal.lifecycle_events(
    portal_id, previous_state, next_state, actor_id, reason, reference,
    configuration_revision
  ) values (
    current_config.portal_id, current_config.lifecycle_state, target, auth.uid(),
    btrim(p_reason), nullif(btrim(p_reference), ''), next_revision
  );
  return next_revision;
end
$$;

revoke all on function community_orgs.update_portal_configuration(text,text,text,text,text,bigint)
  from public, anon, authenticated, service_role;
revoke all on function community_orgs.transition_portal_lifecycle(text,text,text,bigint)
  from public, anon, authenticated, service_role;
grant execute on function community_orgs.update_portal_configuration(text,text,text,text,text,bigint)
  to authenticated;
grant execute on function community_orgs.transition_portal_lifecycle(text,text,text,bigint)
  to authenticated;
