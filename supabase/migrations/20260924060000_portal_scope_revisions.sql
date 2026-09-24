-- PEG02: one immutable, postcode-defined scope history per isolated portal.
create table portal.scope_revisions (
  id bigint generated always as identity primary key,
  portal_id uuid not null references portal.configuration(portal_id) on delete restrict,
  revision bigint not null check (revision > 0),
  previous_revision_id bigint references portal.scope_revisions(id) on delete restrict,
  inclusion_policy_version text not null check (btrim(inclusion_policy_version) <> ''),
  impact_assessment text not null check (btrim(impact_assessment) <> ''),
  requires_rebaseline boolean not null,
  effective_at timestamptz not null default now(),
  approved_at timestamptz not null default now(),
  approved_by uuid references auth.users(id) on delete restrict,
  reason text not null check (btrim(reason) <> ''),
  unique (portal_id, revision),
  unique (id, portal_id),
  check ((revision = 1 and previous_revision_id is null)
    or (revision > 1 and previous_revision_id is not null))
);

create table portal.scope_postcodes (
  scope_revision_id bigint not null references portal.scope_revisions(id) on delete restrict,
  postcode text not null check (postcode ~ '^[0-9]{4}$'),
  primary key (scope_revision_id, postcode)
);

alter table portal.configuration
  add column current_scope_revision_id bigint,
  add constraint configuration_current_scope_revision_fkey
    foreign key (current_scope_revision_id, portal_id)
    references portal.scope_revisions(id, portal_id) on delete restrict;

comment on column portal.configuration.scope_reference is
  'Deprecated PEG01 establishment bridge retained for compatibility; current_scope_revision_id is authoritative.';
comment on table portal.scope_revisions is
  'Append-only approved portal scope history. A revision change never discovers or publishes organisations by itself.';
comment on table portal.scope_postcodes is
  'Canonical postcode membership for an immutable portal scope revision.';

alter table portal.scope_revisions enable row level security;
alter table portal.scope_postcodes enable row level security;
revoke all on portal.scope_revisions, portal.scope_postcodes
  from public, anon, authenticated, service_role;
revoke all on sequence portal.scope_revisions_id_seq
  from public, anon, authenticated, service_role;

create function portal.reject_scope_mutation() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'Portal scope history is append-only' using errcode = '55000';
end
$$;

create trigger scope_revisions_immutable
before update or delete on portal.scope_revisions
for each row execute function portal.reject_scope_mutation();
create trigger scope_postcodes_immutable
before update or delete on portal.scope_postcodes
for each row execute function portal.reject_scope_mutation();

-- Preserve the approved scope already used by this deployment. This is
-- conditional so a fresh unestablished database still starts without identity.
do $$
declare
  configured_portal portal.configuration%rowtype;
  scope_id bigint;
begin
  select * into configured_portal from portal.configuration where singleton;
  if found then
    insert into portal.scope_revisions(
      portal_id, revision, inclusion_policy_version, impact_assessment,
      requires_rebaseline, effective_at, approved_by, reason
    ) values (
      configured_portal.portal_id, 1, 'legacy-portal-scope-v1',
      'Backfilled from the approved 23-postcode acquisition and seed configuration.',
      false, configured_portal.established_at,
      coalesce(configured_portal.updated_by, configured_portal.established_by),
      'PEG02 authoritative scope revision 1 backfill'
    ) returning id into scope_id;

    insert into portal.scope_postcodes(scope_revision_id, postcode)
    select scope_id, unnest(array[
      '2582','2611','2620','2624','2627','2628','2629','2640','2642','2644','2649','2650',
      '2652','2653','2720','2722','2727','2729','2730','3707','3708','3709','3900'
    ]::text[]);

    update portal.configuration
    set current_scope_revision_id = scope_id,
        configuration_revision = configuration_revision + 1,
        updated_at = now()
    where singleton;
  end if;
end
$$;

create function community_orgs.configure_portal_scope(
  p_postcodes text[],
  p_inclusion_policy_version text,
  p_reason text,
  p_impact_assessment text,
  p_requires_rebaseline boolean,
  p_expected_revision bigint default null
) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  current_config portal.configuration%rowtype;
  previous_scope portal.scope_revisions%rowtype;
  canonical text[];
  next_scope_id bigint;
  next_scope_revision bigint;
begin
  if community_orgs.is_platform_admin() is distinct from true then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  select array_agg(postcode order by postcode) into canonical
  from (select distinct unnest(p_postcodes) as postcode) values_to_sort;
  if p_postcodes is null or cardinality(p_postcodes) not between 1 and 500
     or array_position(p_postcodes, null) is not null
     or exists (select 1 from unnest(p_postcodes) postcode where postcode !~ '^[0-9]{4}$')
     or p_postcodes is distinct from canonical
     or nullif(btrim(p_inclusion_policy_version), '') is null
     or length(p_inclusion_policy_version) > 200
     or nullif(btrim(p_reason), '') is null or length(p_reason) > 2000
     or nullif(btrim(p_impact_assessment), '') is null or length(p_impact_assessment) > 4000
     or p_requires_rebaseline is null then
    raise exception 'Canonical postcodes, policy, impact, reason and rebaseline decision are required'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(24060000);
  select * into current_config from portal.configuration where singleton for update;
  if not found then
    raise exception 'Portal identity is not configured' using errcode = 'P0002';
  end if;
  if p_expected_revision is not null
     and current_config.configuration_revision <> p_expected_revision then
    raise exception 'Portal configuration changed; reload before saving' using errcode = '40001';
  end if;
  if current_config.current_scope_revision_id is not null then
    select * into previous_scope from portal.scope_revisions
    where id = current_config.current_scope_revision_id;
    if not exists (
      (select postcode from portal.scope_postcodes where scope_revision_id = previous_scope.id
       except select unnest(p_postcodes))
      union all
      (select unnest(p_postcodes)
       except select postcode from portal.scope_postcodes where scope_revision_id = previous_scope.id)
    ) then
      raise exception 'The postcode set is unchanged' using errcode = '22023';
    end if;
    next_scope_revision := previous_scope.revision + 1;
  else
    next_scope_revision := 1;
  end if;

  insert into portal.scope_revisions(
    portal_id, revision, previous_revision_id, inclusion_policy_version,
    impact_assessment, requires_rebaseline, approved_by, reason
  ) values (
    current_config.portal_id, next_scope_revision, previous_scope.id,
    btrim(p_inclusion_policy_version), btrim(p_impact_assessment),
    p_requires_rebaseline, auth.uid(), btrim(p_reason)
  ) returning id into next_scope_id;
  insert into portal.scope_postcodes(scope_revision_id, postcode)
  select next_scope_id, unnest(p_postcodes);

  update portal.configuration
  set current_scope_revision_id = next_scope_id,
      configuration_revision = configuration_revision + 1,
      updated_at = now(), updated_by = auth.uid()
  where singleton;

  -- Work already queued against the former boundary must not continue.
  update ingestion.acquisition_jobs
  set status = 'cancelled', finished_at = now(), lease_token = null,
      lease_until = null, message = 'Portal scope revision changed.'
  where status in ('queued', 'running');
  return next_scope_id;
end
$$;

create function community_orgs.portal_scope_history()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if community_orgs.is_platform_admin() is distinct from true then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'configuration_revision', (select configuration_revision from portal.configuration where singleton),
    'current_scope_revision_id', (select current_scope_revision_id::text from portal.configuration where singleton),
    'revisions', coalesce((select jsonb_agg(jsonb_build_object(
      'id', r.id::text, 'revision', r.revision::text,
      'postcodes', (select jsonb_agg(p.postcode order by p.postcode)
        from portal.scope_postcodes p where p.scope_revision_id = r.id),
      'inclusion_policy_version', r.inclusion_policy_version,
      'impact_assessment', r.impact_assessment,
      'requires_rebaseline', r.requires_rebaseline,
      'effective_at', r.effective_at, 'approved_at', r.approved_at,
      'approved_by', r.approved_by, 'reason', r.reason,
      'current', r.id = c.current_scope_revision_id
    ) order by r.revision desc)
    from portal.scope_revisions r join portal.configuration c on c.portal_id = r.portal_id), '[]'::jsonb)
  );
end
$$;

-- Make lifecycle scope evidence authoritative. The text reference remains an
-- optional human reference and is no longer sufficient by itself.
create or replace function community_orgs.transition_portal_lifecycle(
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
  begin target := p_next_state::portal.lifecycle_state;
  exception when invalid_text_representation then
    raise exception 'Invalid portal lifecycle state' using errcode = '22023';
  end;
  select * into current_config from portal.configuration where singleton for update;
  if not found then raise exception 'Portal identity is not configured' using errcode = 'P0002'; end if;
  if p_expected_revision is not null and current_config.configuration_revision <> p_expected_revision then
    raise exception 'Portal configuration changed; reload before saving' using errcode = '40001';
  end if;
  if target = current_config.lifecycle_state then return current_config.configuration_revision; end if;
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
    raise exception 'Invalid portal lifecycle transition: % to %', current_config.lifecycle_state, target
      using errcode = '22023';
  end if;
  if target = 'scope_configured' and current_config.current_scope_revision_id is null then
    raise exception 'An authoritative portal scope revision is required' using errcode = '22023';
  end if;
  next_revision := current_config.configuration_revision + 1;
  update portal.configuration
  set lifecycle_state = target,
      scope_reference = case when target = 'scope_configured'
        then coalesce(nullif(btrim(p_reference), ''), 'scope-revision-' || current_scope_revision_id::text)
        else scope_reference end,
      configuration_revision = next_revision, updated_at = now(), updated_by = auth.uid()
  where singleton;
  insert into portal.lifecycle_events(
    portal_id, previous_state, next_state, actor_id, reason, reference, configuration_revision
  ) values (
    current_config.portal_id, current_config.lifecycle_state, target, auth.uid(), btrim(p_reason),
    coalesce(nullif(btrim(p_reference), ''),
      case when target = 'scope_configured' then 'scope-revision-' || current_config.current_scope_revision_id::text end),
    next_revision
  );
  return next_revision;
end
$$;

-- Bind every acquisition configuration and job to an approved portal scope.
alter table ingestion.acquisition_configs
  add column scope_revision_id bigint references portal.scope_revisions(id) on delete restrict,
  add column scope_alignment text check (scope_alignment in ('exact', 'subset', 'superset')),
  add column scope_exception_reason text;

update ingestion.acquisition_configs c
set scope_revision_id = p.current_scope_revision_id,
    scope_alignment = case
      when c.postcodes = (select array_agg(postcode order by postcode)
        from portal.scope_postcodes where scope_revision_id = p.current_scope_revision_id) then 'exact'
      when c.postcodes <@ (select array_agg(postcode order by postcode)
        from portal.scope_postcodes where scope_revision_id = p.current_scope_revision_id) then 'subset'
      when (select array_agg(postcode order by postcode)
        from portal.scope_postcodes where scope_revision_id = p.current_scope_revision_id) <@ c.postcodes then 'superset'
      else null
    end,
    scope_exception_reason = case
      when c.postcodes = (select array_agg(postcode order by postcode)
        from portal.scope_postcodes where scope_revision_id = p.current_scope_revision_id) then null
      else 'Legacy configuration retained during PEG02 scope backfill' end
from portal.configuration p
where p.singleton;

alter table ingestion.acquisition_configs
  alter column scope_revision_id set not null,
  alter column scope_alignment set not null,
  add constraint acquisition_scope_exception_check check (
    (scope_alignment = 'exact' and scope_exception_reason is null)
    or (scope_alignment in ('subset', 'superset')
      and length(btrim(scope_exception_reason)) between 1 and 2000)
  );

-- Attribute pre-PEG02 completed acquisition jobs without rewriting their
-- retained source envelope. New jobs also write this FK-backed attribution.
create table ingestion.run_scope_attributions (
  run_id bigint primary key references ingestion.ingestion_runs(id) on delete restrict,
  scope_revision_id bigint not null references portal.scope_revisions(id) on delete restrict,
  alignment text not null check (alignment in ('exact', 'subset', 'superset')),
  reason text not null check (btrim(reason) <> ''),
  attributed_at timestamptz not null default now(),
  attributed_by uuid references auth.users(id) on delete restrict
);
alter table ingestion.run_scope_attributions enable row level security;
revoke all on ingestion.run_scope_attributions from public, anon, authenticated, service_role, ingestion_worker;
create trigger run_scope_attributions_immutable
before update or delete on ingestion.run_scope_attributions
for each row execute function portal.reject_scope_mutation();

insert into ingestion.run_scope_attributions(run_id, scope_revision_id, alignment, reason)
select j.run_id, c.scope_revision_id, c.scope_alignment,
  'PEG02 backfill from the acquisition job and approved portal scope revision 1'
from ingestion.acquisition_jobs j
join ingestion.acquisition_configs c using(source_id, resource_id)
where j.run_id is not null
on conflict (run_id) do nothing;

create or replace function community_orgs.configure_acnc_acquisition(
  p_resource text, p_postcodes text[], p_licence text, p_interval integer,
  p_revision text, p_scope_exception_reason text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  c ingestion.acquisition_configs;
  s ingestion.sources;
  configured_portal portal.configuration%rowtype;
  canonical text[];
  portal_postcodes text[];
  alignment text;
begin
  if community_orgs.is_platform_admin() is distinct from true then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(17093000);
  select * into s from ingestion.sources
    where source_id = 'acnc-register' and resource_id = p_resource for share;
  if not found or coalesce(s.metadata->>'synthetic', 'false') <> 'false' then
    raise exception 'Live ACNC source required' using errcode = '22023';
  end if;
  perform p_resource::uuid;
  select * into configured_portal from portal.configuration where singleton for share;
  if not found or configured_portal.current_scope_revision_id is null then
    raise exception 'Configure the authoritative portal scope first' using errcode = '55000';
  end if;
  select array_agg(postcode order by postcode) into portal_postcodes
    from portal.scope_postcodes where scope_revision_id = configured_portal.current_scope_revision_id;
  select array_agg(x order by x) into canonical from (select distinct unnest(p_postcodes) x) values_to_sort;
  if p_postcodes is null or cardinality(p_postcodes) not between 1 and 50
     or array_position(p_postcodes, null) is not null
     or exists (select 1 from unnest(p_postcodes) x where x !~ '^[0-9]{4}$')
     or p_postcodes is distinct from canonical
     or p_licence is null or length(trim(p_licence)) not between 1 and 300
     or (p_interval is not null and p_interval not in (24, 168, 720)) then
    raise exception 'Invalid acquisition configuration' using errcode = '22023';
  end if;
  alignment := case
    when p_postcodes = portal_postcodes then 'exact'
    when p_postcodes <@ portal_postcodes then 'subset'
    when portal_postcodes <@ p_postcodes then 'superset'
    else null end;
  if alignment is null then
    raise exception 'Acquisition postcodes must be the portal scope or a true subset/superset'
      using errcode = '22023';
  end if;
  if alignment <> 'exact' and coalesce(length(btrim(p_scope_exception_reason)), 0) not between 1 and 2000 then
    raise exception 'A justified scope exception is required for a % configuration', alignment
      using errcode = '22023';
  end if;
  select * into c from ingestion.acquisition_configs
    where source_id = 'acnc-register' and resource_id = p_resource for update;
  if coalesce(c.revision, 0)::text is distinct from p_revision then
    raise exception 'Configuration changed' using errcode = '40001';
  end if;
  insert into ingestion.acquisition_configs(
    resource_id, postcodes, licence_title, interval_hours, next_due_at, updated_by,
    scope_revision_id, scope_alignment, scope_exception_reason
  ) values (
    p_resource, p_postcodes, trim(p_licence), p_interval,
    case when p_interval is not null then now() + make_interval(hours => p_interval) end,
    auth.uid(), configured_portal.current_scope_revision_id, alignment,
    case when alignment = 'exact' then null else btrim(p_scope_exception_reason) end
  ) on conflict(source_id, resource_id) do update set
    postcodes = excluded.postcodes, licence_title = excluded.licence_title,
    interval_hours = excluded.interval_hours, next_due_at = excluded.next_due_at,
    scope_revision_id = excluded.scope_revision_id, scope_alignment = excluded.scope_alignment,
    scope_exception_reason = excluded.scope_exception_reason,
    revision = ingestion.acquisition_configs.revision + 1,
    updated_by = excluded.updated_by, updated_at = now();
  insert into ingestion.acquisition_config_events(source_id, resource_id, revision, configuration, changed_by)
  select source_id, resource_id, revision, to_jsonb(x), auth.uid()
    from ingestion.acquisition_configs x
    where source_id = 'acnc-register' and resource_id = p_resource;
  update ingestion.acquisition_jobs
  set status = 'cancelled', finished_at = now(), lease_token = null, lease_until = null,
      message = 'Acquisition configuration changed.'
  where source_id = 'acnc-register' and resource_id = p_resource and status in ('queued', 'running');
end
$$;

-- Rolling-deployment compatibility: the old call remains valid for exact scope.
create or replace function community_orgs.configure_acnc_acquisition(
  p_resource text, p_postcodes text[], p_licence text, p_interval integer, p_revision text
) returns void language sql security definer set search_path = '' as $$
  select community_orgs.configure_acnc_acquisition(
    p_resource, p_postcodes, p_licence, p_interval, p_revision, null
  )
$$;

create or replace function ingestion.enqueue_acnc(p_resource text, p_origin text, p_actor uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare c ingestion.acquisition_configs; s ingestion.sources; job uuid; current_scope bigint;
begin
  perform pg_advisory_xact_lock(17093000);
  select * into s from ingestion.sources where source_id = 'acnc-register' and resource_id = p_resource for share;
  if not found or not s.enabled then raise exception 'Source paused' using errcode = '55000'; end if;
  select * into c from ingestion.acquisition_configs where source_id = s.source_id and resource_id = s.resource_id;
  if not found then raise exception 'Configure acquisition first' using errcode = '55000'; end if;
  select current_scope_revision_id into current_scope from portal.configuration where singleton;
  if current_scope is null or c.scope_revision_id <> current_scope then
    raise exception 'Acquisition configuration uses an obsolete portal scope revision' using errcode = '55000';
  end if;
  update ingestion.acquisition_jobs set status = 'cancelled', finished_at = now(),
    message = 'Source approval changed.', lease_token = null, lease_until = null
  where source_id = s.source_id and resource_id = s.resource_id and status in ('queued', 'running')
    and source_revision <> s.approval_revision;
  select id into job from ingestion.acquisition_jobs
    where source_id = s.source_id and resource_id = s.resource_id and status in ('queued', 'running');
  if job is not null then return job; end if;
  insert into ingestion.acquisition_jobs(
    source_id, resource_id, config_revision, source_revision, config, origin, requested_by
  ) values (
    s.source_id, s.resource_id, c.revision, s.approval_revision,
    jsonb_build_object(
      'enabled', true, 'resource_id', c.resource_id, 'postcodes', to_jsonb(c.postcodes),
      'portal_scope_revision_id', c.scope_revision_id::text,
      'scope_alignment', c.scope_alignment,
      'scope_exception_reason', c.scope_exception_reason,
      'expected_licence_title', c.licence_title, 'page_size', 100, 'max_pages', 10,
      'timeout_seconds', 10, 'deadline_seconds', 120, 'max_response_bytes', 2097152
    ), p_origin, p_actor
  ) returning id into job;
  return job;
end
$$;

create or replace function community_orgs.acquisition_dashboard() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if community_orgs.is_ingestion_operator() is distinct from true then
    raise exception 'Operator required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'portal_scope_revision_id', (select current_scope_revision_id::text from portal.configuration where singleton),
    'sources', coalesce((select jsonb_agg(jsonb_build_object(
      'resource_id', s.resource_id, 'enabled', s.enabled,
      'title', coalesce(s.metadata->>'public_title', s.source_id),
      'postcodes', c.postcodes, 'licence_title', coalesce(c.licence_title, s.metadata->>'public_licence', ''),
      'interval_hours', c.interval_hours, 'next_due_at', c.next_due_at,
      'revision', coalesce(c.revision, 0)::text,
      'scope_revision_id', c.scope_revision_id::text, 'scope_alignment', c.scope_alignment,
      'scope_exception_reason', c.scope_exception_reason
    ) order by s.resource_id)
    from ingestion.sources s left join ingestion.acquisition_configs c using(source_id, resource_id)
    where s.source_id = 'acnc-register' and coalesce(s.metadata->>'synthetic', 'false') = 'false'), '[]'::jsonb),
    'jobs', coalesce((select jsonb_agg(to_jsonb(j)) from (
      select id::text, resource_id, status, origin, attempts, created_at, available_at, lease_until,
        finished_at, run_id::text, message, checkpoint is not null as acquired
      from ingestion.acquisition_jobs order by created_at desc limit 50
    ) j), '[]'::jsonb)
  );
end
$$;

create or replace function ingestion.checkpoint_acquisition(
  p_job uuid, p_token uuid, p_envelope jsonb
) returns void language plpgsql security definer set search_path = '' as $$
declare j ingestion.acquisition_jobs;
begin
  j := ingestion.lock_acquisition(p_job, p_token);
  if p_envelope->>'run_id' is distinct from 'acnc-job-' || j.id::text
     or p_envelope->>'source_id' is distinct from j.source_id
     or p_envelope->>'resource_id' is distinct from j.resource_id
     or p_envelope->'scope' is distinct from jsonb_build_object(
       'kind', 'filtered-resource',
       'portal_scope_revision_id', j.config->>'portal_scope_revision_id',
       'alignment', j.config->>'scope_alignment',
       'complete_snapshot', false,
       'filters', jsonb_build_object('Postcode', j.config->'postcodes'))
     or p_envelope->'qualification'->'limits' is distinct from j.config
     or p_envelope->'publication_eligible' is distinct from 'false'::jsonb
     or coalesce(p_envelope->>'completion', '') not in ('complete', 'partial', 'failed')
     or p_envelope->>'parser_version' is distinct from 'acnc-ckan-v3'
     or coalesce((p_envelope->>'synthetic')::boolean, true)
     or (p_envelope->>'observed_at')::timestamptz < j.created_at
     or (p_envelope->>'observed_at')::timestamptz > now() + interval '1 minute'
     or p_envelope->>'observed_at' is null then
    raise exception 'Envelope does not match job' using errcode = '22023';
  end if;
  if j.checkpoint is not null and j.checkpoint is distinct from p_envelope then
    raise exception 'Checkpoint immutable' using errcode = '40001';
  end if;
  update ingestion.acquisition_jobs
  set checkpoint = p_envelope, lease_until = now() + interval '5 minutes' where id = p_job;
end
$$;

create or replace function ingestion.finish_acquisition(p_job uuid, p_token uuid)
returns bigint language plpgsql security definer set search_path = '' as $$
declare j ingestion.acquisition_jobs; r bigint;
begin
  j := ingestion.lock_acquisition(p_job, p_token);
  if j.checkpoint is null then raise exception 'Acquisition checkpoint required'; end if;
  r := ingestion.stage_acnc(j.checkpoint);
  insert into ingestion.run_scope_attributions(
    run_id, scope_revision_id, alignment, reason, attributed_by
  ) values (
    r, (j.config->>'portal_scope_revision_id')::bigint,
    j.config->>'scope_alignment', 'Recorded atomically from the fenced acquisition job', j.requested_by
  ) on conflict (run_id) do nothing;
  update ingestion.acquisition_jobs
  set status = j.checkpoint->>'completion', run_id = r, finished_at = now(),
      lease_token = null, lease_until = null,
      message = case when j.checkpoint->>'completion' = 'complete' then 'Ready for review.'
        else 'Incomplete acquisition; inspect the retained import errors. Publication is blocked.' end
  where id = p_job;
  return r;
end
$$;

create function ingestion.run_portal_scope_revision(p_run ingestion.ingestion_runs)
returns bigint language sql stable security definer set search_path = '' as $$
  select coalesce(
    case when p_run.envelope->'scope'->>'portal_scope_revision_id' ~ '^[0-9]+$'
      then (p_run.envelope->'scope'->>'portal_scope_revision_id')::bigint end,
    (select a.scope_revision_id from ingestion.run_scope_attributions a where a.run_id = p_run.id)
  )
$$;

-- Portal scope revision is part of snapshot comparability, even for provider
-- scope objects that contain otherwise identical filters.
create or replace function ingestion.reconciliation_missing_reason(p_run bigint, p_baseline bigint)
returns text language plpgsql stable security definer set search_path = '' as $$
declare r ingestion.ingestion_runs; b ingestion.ingestion_runs;
begin
  select * into r from ingestion.ingestion_runs where id = p_run;
  if not found then raise exception 'Run not found' using errcode = 'P0002'; end if;
  select * into b from ingestion.ingestion_runs where id = p_baseline;
  if not found then raise exception 'Baseline not found' using errcode = 'P0002'; end if;
  if ingestion.run_portal_scope_revision(b) is null
     or ingestion.run_portal_scope_revision(r) is null then
    return 'Both runs must be attributable to an authoritative portal scope revision';
  end if;
  if ingestion.run_portal_scope_revision(b)
       is distinct from ingestion.run_portal_scope_revision(r) then
    return 'Baseline uses an incompatible portal scope revision; start a scope rebaseline campaign';
  end if;
  if (b.source_id, b.resource_id) is distinct from (r.source_id, r.resource_id)
     or b.id = r.id or b.observed_at >= r.observed_at
     or ingestion.complete_snapshot_scope_key(b.envelope->'scope')
       is distinct from ingestion.complete_snapshot_scope_key(r.envelope->'scope') then
    return 'Baseline must be an earlier observation of the same source, resource and scope';
  end if;
  if r.completion <> 'complete' or b.completion <> 'complete' then
    return 'Incomplete run; absence cannot be assessed';
  end if;
  if jsonb_array_length(coalesce(r.envelope->'errors', '[]'::jsonb)) > 0
     or jsonb_array_length(coalesce(r.envelope->'quarantine', '[]'::jsonb)) > 0
     or jsonb_array_length(coalesce(b.envelope->'errors', '[]'::jsonb)) > 0
     or jsonb_array_length(coalesce(b.envelope->'quarantine', '[]'::jsonb)) > 0 then
    return 'Snapshot contains errors or quarantine';
  end if;
  if r.raw_removed_at is not null or b.raw_removed_at is not null then
    return 'Retained evidence was purged';
  end if;
  if not exists (select 1 from ingestion.complete_snapshot_sources q
    where q.source_id = r.source_id and q.resource_id = r.resource_id
      and q.scope is not distinct from ingestion.complete_snapshot_scope_key(r.envelope->'scope')
      and q.active) then
    return 'Source scope is not qualified as a complete snapshot';
  end if;
  return null;
end
$$;

-- Extend the request-boundary identity result with schema and current scope.
drop function community_orgs.get_portal_identity();
create function community_orgs.get_portal_identity()
returns table (
  portal_id uuid, portal_key text, display_name text, short_name text,
  sponsor_name text, sponsor_url text, logo_url text, lifecycle_state text,
  configuration_revision bigint, schema_version text,
  scope_revision_id bigint, scope_revision bigint, scope_postcodes text[]
)
language sql stable security definer set search_path = '' as $$
  select c.portal_id, c.portal_key, c.display_name, c.short_name,
    c.sponsor_name, c.sponsor_url, c.logo_url, c.lifecycle_state::text,
    c.configuration_revision, '20260924060000', r.id, r.revision,
    (select array_agg(p.postcode order by p.postcode)
      from portal.scope_postcodes p where p.scope_revision_id = r.id)
  from portal.configuration c
  left join portal.scope_revisions r on r.id = c.current_scope_revision_id
  where c.singleton
$$;

revoke all on function community_orgs.configure_portal_scope(text[],text,text,text,boolean,bigint),
  community_orgs.portal_scope_history(),
  community_orgs.configure_acnc_acquisition(text,text[],text,integer,text,text),
  community_orgs.configure_acnc_acquisition(text,text[],text,integer,text),
  community_orgs.get_portal_identity()
  from public, anon, authenticated, service_role;
revoke all on function ingestion.run_portal_scope_revision(ingestion.ingestion_runs)
  from public, anon, authenticated, service_role, ingestion_worker;
grant execute on function community_orgs.configure_portal_scope(text[],text,text,text,boolean,bigint),
  community_orgs.portal_scope_history(),
  community_orgs.configure_acnc_acquisition(text,text[],text,integer,text,text),
  community_orgs.configure_acnc_acquisition(text,text[],text,integer,text)
  to authenticated;
grant execute on function community_orgs.get_portal_identity() to anon, authenticated, service_role;
