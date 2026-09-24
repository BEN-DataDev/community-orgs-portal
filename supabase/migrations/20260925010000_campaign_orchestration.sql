-- PEG09 / Phase 4: immutable campaign scope and source pins with derived readiness.
-- Campaigns orchestrate existing evidence. They do not copy source payloads,
-- validation evidence, review decisions, field approvals or release contents.

create table portal.campaigns (
  campaign_id uuid primary key default gen_random_uuid(),
  portal_id uuid not null references portal.configuration(portal_id) on delete restrict,
  campaign_type text not null check (campaign_type in (
    'initial_seed', 'scheduled_refresh', 'scope_rebaseline', 'correction',
    'withdrawal', 'source_reprocessing'
  )),
  name text not null check (length(btrim(name)) between 1 and 200),
  scope_revision_id bigint not null,
  inclusion_policy_version text not null check (length(btrim(inclusion_policy_version)) between 1 and 200),
  mapping_versions jsonb not null check (
    jsonb_typeof(mapping_versions) = 'object' and mapping_versions <> '{}'::jsonb
  ),
  approval_policy_revision bigint not null
    references portal.publication_approval_policy_events(revision) on delete restrict,
  scheduled_for timestamptz,
  replaces_campaign_id uuid references portal.campaigns(campaign_id) on delete restrict,
  reason text not null check (length(btrim(reason)) between 1 and 2000),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  unique (campaign_id, portal_id),
  foreign key (scope_revision_id, portal_id)
    references portal.scope_revisions(id, portal_id) on delete restrict,
  check (replaces_campaign_id is null or replaces_campaign_id <> campaign_id)
);

create table ingestion.campaign_source_artifacts (
  artifact_id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references portal.campaigns(campaign_id) on delete restrict,
  position integer not null check (position between 1 and 100),
  purpose text not null check (length(btrim(purpose)) between 1 and 200),
  artifact_kind text not null check (artifact_kind in ('ingestion_run', 'registry_seed_release')),
  ingestion_run_id bigint references ingestion.ingestion_runs(id) on delete restrict,
  registry_seed_release_id bigint references ingestion.registry_seed_releases(id) on delete restrict,
  source_id text not null,
  resource_id text not null,
  artifact_key text not null,
  parser_version text not null,
  observed_at timestamptz not null,
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  required boolean not null default true,
  pinned_at timestamptz not null default now(),
  pinned_by uuid not null references auth.users(id) on delete restrict,
  unique (campaign_id, position),
  check ((artifact_kind = 'ingestion_run' and ingestion_run_id is not null and registry_seed_release_id is null)
    or (artifact_kind = 'registry_seed_release' and registry_seed_release_id is not null and ingestion_run_id is null))
);

-- Replacements are global source-evidence facts. A campaign keeps its original
-- pin; readiness observes this event and becomes stale without rewriting it.
create table ingestion.source_artifact_replacements (
  replacement_id uuid primary key default gen_random_uuid(),
  artifact_kind text not null check (artifact_kind in ('ingestion_run', 'registry_seed_release')),
  replaced_ingestion_run_id bigint references ingestion.ingestion_runs(id) on delete restrict,
  replacement_ingestion_run_id bigint references ingestion.ingestion_runs(id) on delete restrict,
  replaced_registry_seed_release_id bigint references ingestion.registry_seed_releases(id) on delete restrict,
  replacement_registry_seed_release_id bigint references ingestion.registry_seed_releases(id) on delete restrict,
  reason text not null check (length(btrim(reason)) between 1 and 2000),
  recorded_at timestamptz not null default now(),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  check ((artifact_kind = 'ingestion_run'
      and replaced_ingestion_run_id is not null and replacement_ingestion_run_id is not null
      and replaced_registry_seed_release_id is null and replacement_registry_seed_release_id is null
      and replaced_ingestion_run_id <> replacement_ingestion_run_id)
    or (artifact_kind = 'registry_seed_release'
      and replaced_registry_seed_release_id is not null and replacement_registry_seed_release_id is not null
      and replaced_ingestion_run_id is null and replacement_ingestion_run_id is null
      and replaced_registry_seed_release_id <> replacement_registry_seed_release_id))
);
create unique index source_artifact_replacements_run_once
  on ingestion.source_artifact_replacements(replaced_ingestion_run_id)
  where artifact_kind = 'ingestion_run';
create unique index source_artifact_replacements_release_once
  on ingestion.source_artifact_replacements(replaced_registry_seed_release_id)
  where artifact_kind = 'registry_seed_release';

create table ingestion.campaign_publication_releases (
  campaign_id uuid not null references portal.campaigns(campaign_id) on delete restrict,
  release_id uuid not null unique references ingestion.publication_releases(release_id) on delete restrict,
  linked_at timestamptz not null default now(),
  linked_by uuid not null references auth.users(id) on delete restrict,
  primary key (campaign_id, release_id)
);

create index campaigns_created_idx on portal.campaigns(created_at desc);
create index campaign_artifacts_campaign_idx on ingestion.campaign_source_artifacts(campaign_id, position);
create unique index campaign_artifacts_run_once
  on ingestion.campaign_source_artifacts(campaign_id, ingestion_run_id)
  where artifact_kind = 'ingestion_run';
create unique index campaign_artifacts_registry_release_once
  on ingestion.campaign_source_artifacts(campaign_id, registry_seed_release_id)
  where artifact_kind = 'registry_seed_release';
create index campaign_releases_campaign_idx on ingestion.campaign_publication_releases(campaign_id, linked_at);

alter table portal.campaigns enable row level security;
alter table ingestion.campaign_source_artifacts enable row level security;
alter table ingestion.source_artifact_replacements enable row level security;
alter table ingestion.campaign_publication_releases enable row level security;
revoke all on portal.campaigns, ingestion.campaign_source_artifacts,
  ingestion.source_artifact_replacements, ingestion.campaign_publication_releases
  from public, anon, authenticated, service_role, ingestion_worker;

create function ingestion.reject_campaign_evidence_mutation() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'Campaign evidence is append-only' using errcode = '55000';
end
$$;
create trigger campaigns_immutable before update or delete on portal.campaigns
  for each row execute function ingestion.reject_campaign_evidence_mutation();
create trigger campaign_artifacts_immutable before update or delete on ingestion.campaign_source_artifacts
  for each row execute function ingestion.reject_campaign_evidence_mutation();
create trigger source_artifact_replacements_immutable before update or delete on ingestion.source_artifact_replacements
  for each row execute function ingestion.reject_campaign_evidence_mutation();
create trigger campaign_publication_releases_immutable before update or delete on ingestion.campaign_publication_releases
  for each row execute function ingestion.reject_campaign_evidence_mutation();
revoke all on function ingestion.reject_campaign_evidence_mutation()
  from public, anon, authenticated, service_role, ingestion_worker;

create function community_orgs.create_campaign(
  p_campaign_type text,
  p_name text,
  p_scope_revision text,
  p_mapping_versions jsonb,
  p_artifacts jsonb,
  p_reason text,
  p_scheduled_for timestamptz default null,
  p_replaces_campaign uuid default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  configured portal.configuration;
  campaign_scope portal.scope_revisions;
  policy_revision bigint;
  campaign uuid;
  artifact jsonb;
  artifact_position integer := 0;
  run ingestion.ingestion_runs;
  registry_release ingestion.registry_seed_releases;
begin
  if community_orgs.is_data_steward() is distinct from true then
    raise exception 'Data Steward required' using errcode = '42501';
  end if;
  if p_campaign_type not in ('initial_seed', 'scheduled_refresh', 'scope_rebaseline',
      'correction', 'withdrawal', 'source_reprocessing')
     or nullif(btrim(p_name), '') is null or length(p_name) > 200
     or nullif(btrim(p_reason), '') is null or length(p_reason) > 2000
     or jsonb_typeof(p_mapping_versions) is distinct from 'object'
     or p_mapping_versions = '{}'::jsonb
     or jsonb_typeof(p_artifacts) is distinct from 'array'
     or jsonb_array_length(p_artifacts) not between 1 and 100 then
    raise exception 'Invalid campaign metadata' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_each(p_mapping_versions) where jsonb_typeof(value) <> 'string'
      or nullif(btrim(value #>> '{}'), '') is null) then
    raise exception 'Mapping versions must be named strings' using errcode = '22023';
  end if;
  select * into configured from portal.configuration where singleton for share;
  if not found then raise exception 'Portal identity is not configured' using errcode = 'P0002'; end if;
  select * into campaign_scope from portal.scope_revisions
    where id = p_scope_revision::bigint and portal_id = configured.portal_id;
  if not found then raise exception 'Portal scope revision not found' using errcode = 'P0002'; end if;
  if p_replaces_campaign is not null and not exists (
    select 1 from portal.campaigns where campaign_id = p_replaces_campaign
      and portal_id = configured.portal_id
  ) then raise exception 'Replaced campaign not found' using errcode = 'P0002'; end if;
  select revision into policy_revision from portal.publication_approval_policy where singleton;

  insert into portal.campaigns(
    portal_id, campaign_type, name, scope_revision_id, inclusion_policy_version,
    mapping_versions, approval_policy_revision, scheduled_for, replaces_campaign_id,
    reason, created_by
  ) values (
    configured.portal_id, p_campaign_type, btrim(p_name), campaign_scope.id,
    campaign_scope.inclusion_policy_version, p_mapping_versions, policy_revision,
    p_scheduled_for, p_replaces_campaign, btrim(p_reason), auth.uid()
  ) returning campaign_id into campaign;

  for artifact in select value from jsonb_array_elements(p_artifacts) loop
    artifact_position := artifact_position + 1;
    if artifact->>'kind' not in ('ingestion_run', 'registry_seed_release')
       or coalesce(artifact->>'id', '') !~ '^[1-9][0-9]{0,18}$'
       or nullif(btrim(artifact->>'purpose'), '') is null
       or length(artifact->>'purpose') > 200
       or (artifact ? 'required' and jsonb_typeof(artifact->'required') <> 'boolean') then
      raise exception 'Invalid campaign source artifact' using errcode = '22023';
    end if;
    if artifact->>'kind' = 'ingestion_run' then
      select * into run from ingestion.ingestion_runs where id = (artifact->>'id')::bigint;
      if not found then raise exception 'Ingestion run not found' using errcode = 'P0002'; end if;
      insert into ingestion.campaign_source_artifacts(
        campaign_id, position, purpose, artifact_kind, ingestion_run_id, source_id,
        resource_id, artifact_key, parser_version, observed_at, evidence_sha256, required, pinned_by
      ) values (
        campaign, artifact_position, btrim(artifact->>'purpose'), 'ingestion_run', run.id,
        run.source_id, run.resource_id, run.run_key, run.envelope->>'parser_version', run.observed_at,
        run.envelope_sha256, coalesce((artifact->>'required')::boolean, true), auth.uid()
      );
    else
      select * into registry_release from ingestion.registry_seed_releases
        where id = (artifact->>'id')::bigint;
      if not found then raise exception 'Registry seed release not found' using errcode = 'P0002'; end if;
      insert into ingestion.campaign_source_artifacts(
        campaign_id, position, purpose, artifact_kind, registry_seed_release_id, source_id,
        resource_id, artifact_key, parser_version, observed_at, evidence_sha256, required, pinned_by
      ) values (
        campaign, artifact_position, btrim(artifact->>'purpose'), 'registry_seed_release',
        registry_release.id, registry_release.source_id, registry_release.resource_id,
        registry_release.release_key, registry_release.parser_version, registry_release.observed_at,
        encode(sha256(convert_to(jsonb_build_object(
          'manifest', registry_release.manifest_sha256,
          'candidates', registry_release.candidate_sha256
        )::text, 'UTF8')), 'hex'), coalesce((artifact->>'required')::boolean, true), auth.uid()
      );
    end if;
  end loop;
  return campaign;
end
$$;

create function community_orgs.record_source_artifact_replacement(
  p_artifact_kind text, p_replaced text, p_replacement text, p_reason text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  old_run ingestion.ingestion_runs;
  new_run ingestion.ingestion_runs;
  old_release ingestion.registry_seed_releases;
  new_release ingestion.registry_seed_releases;
  result uuid;
begin
  if community_orgs.is_data_steward() is distinct from true then
    raise exception 'Data Steward required' using errcode = '42501';
  end if;
  if p_artifact_kind not in ('ingestion_run', 'registry_seed_release')
     or coalesce(p_replaced, '') !~ '^[1-9][0-9]{0,18}$'
     or coalesce(p_replacement, '') !~ '^[1-9][0-9]{0,18}$'
     or p_replaced = p_replacement
     or nullif(btrim(p_reason), '') is null or length(p_reason) > 2000 then
    raise exception 'Invalid source artifact replacement' using errcode = '22023';
  end if;
  if p_artifact_kind = 'ingestion_run' then
    select * into old_run from ingestion.ingestion_runs where id = p_replaced::bigint;
    select * into new_run from ingestion.ingestion_runs where id = p_replacement::bigint;
    if old_run.id is null or new_run.id is null then
      raise exception 'Source artifact not found' using errcode = 'P0002';
    end if;
    if (old_run.source_id, old_run.resource_id) is distinct from
       (new_run.source_id, new_run.resource_id) then
      raise exception 'Replacement must belong to the same source resource' using errcode = '22023';
    end if;
    insert into ingestion.source_artifact_replacements(
      artifact_kind, replaced_ingestion_run_id, replacement_ingestion_run_id, reason, recorded_by
    ) values ('ingestion_run', old_run.id, new_run.id, btrim(p_reason), auth.uid())
    returning replacement_id into result;
  else
    select * into old_release from ingestion.registry_seed_releases where id = p_replaced::bigint;
    select * into new_release from ingestion.registry_seed_releases where id = p_replacement::bigint;
    if old_release.id is null or new_release.id is null then
      raise exception 'Source artifact not found' using errcode = 'P0002';
    end if;
    if (old_release.source_id, old_release.resource_id) is distinct from
       (new_release.source_id, new_release.resource_id) then
      raise exception 'Replacement must belong to the same source resource' using errcode = '22023';
    end if;
    insert into ingestion.source_artifact_replacements(
      artifact_kind, replaced_registry_seed_release_id, replacement_registry_seed_release_id,
      reason, recorded_by
    ) values (
      'registry_seed_release', old_release.id, new_release.id, btrim(p_reason), auth.uid()
    ) returning replacement_id into result;
  end if;
  return result;
end
$$;

create function community_orgs.link_campaign_publication_release(
  p_campaign uuid, p_release uuid
) returns boolean language plpgsql security definer set search_path = '' as $$
declare campaign portal.campaigns; release ingestion.publication_releases;
begin
  if portal.can_govern_publication_releases() is distinct from true then
    raise exception 'Release authority required' using errcode = '42501';
  end if;
  select * into campaign from portal.campaigns where campaign_id = p_campaign;
  if not found then raise exception 'Campaign not found' using errcode = 'P0002'; end if;
  select * into release from ingestion.publication_releases where release_id = p_release;
  if not found then raise exception 'Publication release not found' using errcode = 'P0002'; end if;
  if (campaign.campaign_type = 'initial_seed' and release.release_class <> 'initial_seed')
     or (campaign.campaign_type = 'withdrawal' and release.release_class not in ('suppression', 'destructive'))
     or (campaign.campaign_type not in ('initial_seed', 'withdrawal')
       and release.release_class <> 'ordinary_update') then
    raise exception 'Release class is incompatible with campaign type' using errcode = '22023';
  end if;
  if (ingestion.campaign_readiness(p_campaign)->>'ready')::boolean is distinct from true then
    raise exception 'Campaign is not ready for a publication release' using errcode = '22023';
  end if;
  insert into ingestion.campaign_publication_releases(campaign_id, release_id, linked_by)
  values (p_campaign, p_release, auth.uid());
  return true;
end
$$;

create function ingestion.campaign_readiness(p_campaign uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  campaign portal.campaigns;
  configured portal.configuration;
  artifact ingestion.campaign_source_artifacts;
  blockers jsonb := '[]'::jsonb;
  artifact_count integer := 0;
  record_count bigint := 0;
  validation_blockers bigint := 0;
  identity_pending bigint := 0;
  field_pending bigint := 0;
  release_count bigint := 0;
  published_count bigint := 0;
  replacement jsonb;
  this_count bigint;
begin
  select * into campaign from portal.campaigns where campaign_id = p_campaign;
  if not found then raise exception 'Campaign not found' using errcode = 'P0002'; end if;
  select * into configured from portal.configuration where portal_id = campaign.portal_id;
  if configured.current_scope_revision_id is distinct from campaign.scope_revision_id then
    blockers := blockers || jsonb_build_array(jsonb_build_object(
      'code', 'scope_revision_superseded', 'stage', 'scope',
      'message', 'The campaign is pinned to a superseded portal scope revision.',
      'responsible_role', 'portal_administrator'
    ));
  end if;
  if campaign.approval_policy_revision is distinct from (
    select revision from portal.publication_approval_policy where singleton
  ) then
    blockers := blockers || jsonb_build_array(jsonb_build_object(
      'code', 'approval_policy_superseded', 'stage', 'release',
      'message', 'The campaign is pinned to a superseded publication approval policy.',
      'responsible_role', 'portal_administrator'
    ));
  end if;

  for artifact in select * from ingestion.campaign_source_artifacts
      where campaign_id = p_campaign order by position loop
    artifact_count := artifact_count + 1;
    replacement := null;
    if artifact.artifact_kind = 'ingestion_run' then
      select jsonb_build_object('id', r.replacement_ingestion_run_id::text, 'recorded_at', r.recorded_at)
        into replacement from ingestion.source_artifact_replacements r
        where r.replaced_ingestion_run_id = artifact.ingestion_run_id;
      select count(*) into this_count from ingestion.run_records where run_id = artifact.ingestion_run_id;
      record_count := record_count + this_count;
      if artifact.required and not exists (
        select 1 from ingestion.ingestion_runs r join ingestion.sources s using(source_id, resource_id)
        where r.id = artifact.ingestion_run_id and r.completion = 'complete' and s.enabled
          and r.raw_removed_at is null and r.envelope_sha256 = artifact.evidence_sha256
      ) then
        blockers := blockers || jsonb_build_array(jsonb_build_object(
          'code', 'source_artifact_unavailable', 'stage', 'source',
          'message', format('Required run %s is incomplete, disabled, redacted or changed.', artifact.artifact_key),
          'responsible_role', 'data_steward', 'artifact_id', artifact.artifact_id
        ));
      end if;
      select count(*) into this_count from ingestion.validation_issues i
        left join ingestion.validation_resolutions r on r.issue_id = i.id
        where i.ingestion_run_id = artifact.ingestion_run_id and i.severity = 'blocking'
          and (r.issue_id is null or r.decision = 'defer'
            or not ingestion.validation_category_overridable(i.category));
      validation_blockers := validation_blockers + this_count;
      select count(*) into this_count from ingestion.run_records rr
        left join ingestion.reviews r on r.version_id = rr.version_id
        where rr.run_id = artifact.ingestion_run_id and (r.version_id is null or r.decision = 'defer');
      identity_pending := identity_pending + this_count;
      select count(*) into this_count from ingestion.run_records rr
        join ingestion.reviews r on r.version_id = rr.version_id and r.decision in ('link', 'create')
        where rr.run_id = artifact.ingestion_run_id and not exists (
          select 1 from ingestion.change_sets c
          where c.run_id = rr.run_id and c.version_id = rr.version_id and c.review_revision = r.revision
        );
      field_pending := field_pending + this_count;
    else
      select jsonb_build_object('id', r.replacement_registry_seed_release_id::text, 'recorded_at', r.recorded_at)
        into replacement from ingestion.source_artifact_replacements r
        where r.replaced_registry_seed_release_id = artifact.registry_seed_release_id;
      select count(*) into this_count from ingestion.registry_seed_release_candidates
        where release_id = artifact.registry_seed_release_id;
      record_count := record_count + this_count;
      if artifact.required and not exists (
        select 1 from ingestion.registry_seed_releases r join ingestion.sources s using(source_id, resource_id)
        where r.id = artifact.registry_seed_release_id and r.completion = 'complete' and s.enabled
          and r.raw_removed_at is null and r.completed_part_count = r.expected_part_count
      ) then
        blockers := blockers || jsonb_build_array(jsonb_build_object(
          'code', 'source_artifact_unavailable', 'stage', 'source',
          'message', format('Required registry release %s is incomplete, disabled or redacted.', artifact.artifact_key),
          'responsible_role', 'data_steward', 'artifact_id', artifact.artifact_id
        ));
      end if;
      select count(*) into this_count from ingestion.validation_issues i
        left join ingestion.validation_resolutions r on r.issue_id = i.id
        where i.registry_seed_release_id = artifact.registry_seed_release_id and i.severity = 'blocking'
          and (r.issue_id is null or r.decision = 'defer'
            or not ingestion.validation_category_overridable(i.category));
      validation_blockers := validation_blockers + this_count;
      select count(*) into this_count from ingestion.registry_seed_release_candidates rc
        left join ingestion.registry_seed_triage t on t.version_id = rc.version_id
        where rc.release_id = artifact.registry_seed_release_id and rc.in_scope
          and (t.version_id is null or t.decision = 'defer');
      identity_pending := identity_pending + this_count;
    end if;
    if replacement is not null then
      blockers := blockers || jsonb_build_array(jsonb_build_object(
        'code', 'source_artifact_replaced', 'stage', 'source',
        'message', format('Pinned %s %s has been replaced.', artifact.artifact_kind, artifact.artifact_key),
        'responsible_role', 'data_steward', 'artifact_id', artifact.artifact_id,
        'replacement', replacement
      ));
    end if;
  end loop;
  if artifact_count = 0 then
    blockers := blockers || jsonb_build_array(jsonb_build_object(
      'code', 'source_artifacts_missing', 'stage', 'source',
      'message', 'No source artifacts are pinned.', 'responsible_role', 'data_steward'
    ));
  end if;
  if validation_blockers > 0 then
    blockers := blockers || jsonb_build_array(jsonb_build_object(
      'code', 'validation_blocked', 'stage', 'validation',
      'message', format('%s blocking validation issues require resolution.', validation_blockers),
      'responsible_role', 'data_steward', 'count', validation_blockers
    ));
  end if;
  if identity_pending > 0 then
    blockers := blockers || jsonb_build_array(jsonb_build_object(
      'code', 'identity_pending', 'stage', 'identity',
      'message', format('%s identity or eligibility decisions remain.', identity_pending),
      'responsible_role', 'data_steward', 'count', identity_pending
    ));
  end if;
  if field_pending > 0 then
    blockers := blockers || jsonb_build_array(jsonb_build_object(
      'code', 'field_changes_pending', 'stage', 'changes',
      'message', format('%s reviewed records still need field decisions.', field_pending),
      'responsible_role', 'data_steward', 'count', field_pending
    ));
  end if;
  select count(*), count(*) filter (where r.status = 'published')
    into release_count, published_count
    from ingestion.campaign_publication_releases cr
    join ingestion.publication_releases r using(release_id)
    where cr.campaign_id = p_campaign;
  return jsonb_build_object(
    'ready', jsonb_array_length(blockers) = 0,
    'state', case
      when jsonb_array_length(blockers) > 0 then 'blocked'
      when release_count = 0 then 'ready_for_release'
      when published_count = release_count then 'published'
      else 'release_in_progress'
    end,
    'counts', jsonb_build_object(
      'artifacts', artifact_count, 'records', record_count,
      'validation_blockers', validation_blockers, 'identity_pending', identity_pending,
      'field_changes_pending', field_pending, 'releases', release_count,
      'published_releases', published_count
    ),
    'blockers', blockers
  );
end
$$;
revoke all on function ingestion.campaign_readiness(uuid)
  from public, anon, authenticated, service_role, ingestion_worker;

create function community_orgs.campaign_readiness(p_campaign uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if portal.can_govern_publication_releases() is distinct from true then
    raise exception 'Campaign authority required' using errcode = '42501';
  end if;
  return ingestion.campaign_readiness(p_campaign);
end
$$;

create function community_orgs.campaign_dashboard() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if portal.can_govern_publication_releases() is distinct from true then
    raise exception 'Campaign authority required' using errcode = '42501';
  end if;
  return jsonb_build_object('campaigns', coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
      select c.campaign_id, c.campaign_type, c.name, c.scope_revision_id::text,
        s.revision::text as scope_revision, c.inclusion_policy_version, c.mapping_versions,
        c.approval_policy_revision, c.scheduled_for, c.replaces_campaign_id,
        c.reason, c.created_at, c.created_by, ingestion.campaign_readiness(c.campaign_id) as readiness,
        coalesce((select jsonb_agg(jsonb_build_object(
          'artifact_id', a.artifact_id, 'kind', a.artifact_kind, 'purpose', a.purpose,
          'source_id', a.source_id, 'resource_id', a.resource_id, 'artifact_key', a.artifact_key,
          'parser_version', a.parser_version, 'observed_at', a.observed_at, 'required', a.required
        ) order by a.position) from ingestion.campaign_source_artifacts a
          where a.campaign_id = c.campaign_id), '[]'::jsonb) as artifacts,
        coalesce((select jsonb_agg(jsonb_build_object(
          'release_id', r.release_id, 'release_class', r.release_class, 'status', r.status,
          'revision', r.current_revision, 'linked_at', cr.linked_at
        ) order by cr.linked_at) from ingestion.campaign_publication_releases cr
          join ingestion.publication_releases r using(release_id)
          where cr.campaign_id = c.campaign_id), '[]'::jsonb) as releases
      from portal.campaigns c join portal.scope_revisions s on s.id = c.scope_revision_id
      order by c.created_at desc limit 100
    ) x
  ), '[]'::jsonb));
end
$$;

revoke all on function community_orgs.create_campaign(text, text, text, jsonb, jsonb, text, timestamptz, uuid),
  community_orgs.record_source_artifact_replacement(text, text, text, text),
  community_orgs.link_campaign_publication_release(uuid, uuid),
  community_orgs.campaign_readiness(uuid), community_orgs.campaign_dashboard()
  from public, anon, service_role, ingestion_worker;
grant execute on function community_orgs.create_campaign(text, text, text, jsonb, jsonb, text, timestamptz, uuid),
  community_orgs.record_source_artifact_replacement(text, text, text, text),
  community_orgs.link_campaign_publication_release(uuid, uuid),
  community_orgs.campaign_readiness(uuid), community_orgs.campaign_dashboard()
  to authenticated;

comment on table portal.campaigns is
  'Immutable campaign contract pinning portal scope, inclusion, mapping and approval policy versions.';
comment on table ingestion.campaign_source_artifacts is
  'Immutable references to existing private source evidence; source payloads are never copied here.';
comment on function community_orgs.campaign_readiness(uuid) is
  'Derived campaign readiness and role-labelled blockers over authoritative source and review evidence.';
