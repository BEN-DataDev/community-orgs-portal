-- Pin a bounded registry-seed cohort to an immutable initial-seed campaign.
-- Source artifacts remain complete evidence; readiness work counts only the
-- explicitly selected cohort and never requires bulk exclusion of other records.
begin;

create table ingestion.campaign_registry_cohorts (
  campaign_id uuid primary key references portal.campaigns(campaign_id) on delete restrict,
  artifact_id uuid not null unique references ingestion.campaign_source_artifacts(artifact_id) on delete restrict,
  release_id bigint not null references ingestion.registry_seed_releases(id) on delete restrict,
  selection_version text not null check (length(btrim(selection_version)) between 1 and 200),
  manifest_sha256 text not null check (manifest_sha256 ~ '^[0-9a-f]{64}$'),
  selection_sha256 text not null unique check (selection_sha256 ~ '^[0-9a-f]{64}$'),
  candidate_count integer not null check (candidate_count between 1 and 500),
  reason text not null check (length(btrim(reason)) between 1 and 2000),
  pinned_at timestamptz not null default now(),
  pinned_by uuid not null references auth.users(id) on delete restrict
);

create table ingestion.campaign_registry_cohort_items (
  campaign_id uuid not null references ingestion.campaign_registry_cohorts(campaign_id) on delete restrict,
  ordinal integer not null check (ordinal between 1 and 500),
  version_id bigint not null references ingestion.registry_seed_candidate_versions(id) on delete restrict,
  primary key (campaign_id, version_id),
  unique (campaign_id, ordinal)
);

create index campaign_registry_cohort_items_version_idx
  on ingestion.campaign_registry_cohort_items(version_id);

alter table ingestion.campaign_registry_cohorts enable row level security;
alter table ingestion.campaign_registry_cohort_items enable row level security;
revoke all on ingestion.campaign_registry_cohorts,
  ingestion.campaign_registry_cohort_items
  from public, anon, authenticated, service_role, ingestion_worker;

create trigger campaign_registry_cohorts_immutable
before update or delete on ingestion.campaign_registry_cohorts
for each row execute function ingestion.reject_campaign_evidence_mutation();
create trigger campaign_registry_cohort_items_immutable
before update or delete on ingestion.campaign_registry_cohort_items
for each row execute function ingestion.reject_campaign_evidence_mutation();

create function community_orgs.pin_campaign_registry_cohort(
  p_campaign uuid,
  p_release text,
  p_versions text[],
  p_selection_version text,
  p_manifest_sha256 text,
  p_reason text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  campaign portal.campaigns;
  artifact ingestion.campaign_source_artifacts;
  version_ids bigint[];
  candidate_count integer;
  selection_hash text;
begin
  if community_orgs.is_data_steward() is distinct from true then
    raise exception 'Data Steward required' using errcode = '42501';
  end if;
  if p_release is null or p_release !~ '^[1-9][0-9]{0,18}$'
     or coalesce(array_length(p_versions, 1), 0) not between 1 and 500
     or exists (select 1 from unnest(p_versions) value where value !~ '^[1-9][0-9]{0,18}$')
     or nullif(btrim(p_selection_version), '') is null
     or length(p_selection_version) > 200
     or p_manifest_sha256 !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_reason), '') is null
     or length(p_reason) > 2000 then
    raise exception 'Invalid campaign cohort metadata' using errcode = '22023';
  end if;

  select * into campaign from portal.campaigns where campaign_id = p_campaign for share;
  if not found then raise exception 'Campaign not found' using errcode = 'P0002'; end if;
  if campaign.campaign_type <> 'initial_seed' then
    raise exception 'Registry cohort pins are limited to initial-seed campaigns' using errcode = '22023';
  end if;
  if exists (select 1 from ingestion.campaign_publication_releases where campaign_id = p_campaign) then
    raise exception 'Campaign cohort must be pinned before a publication release' using errcode = '55000';
  end if;
  if exists (select 1 from ingestion.campaign_registry_cohorts where campaign_id = p_campaign) then
    raise exception 'Campaign cohort is already pinned' using errcode = '23505';
  end if;

  select * into artifact
  from ingestion.campaign_source_artifacts
  where campaign_id = p_campaign
    and artifact_kind = 'registry_seed_release'
    and registry_seed_release_id = p_release::bigint
  for share;
  if not found then
    raise exception 'Registry release is not pinned to this campaign' using errcode = '22023';
  end if;
  if artifact.source_id <> 'abr-bulk' then
    raise exception 'The first registry cohort must use the pinned ABR release' using errcode = '22023';
  end if;
  if not exists (
    select 1 from ingestion.registry_seed_releases release
    join ingestion.sources source using(source_id, resource_id)
    where release.id = artifact.registry_seed_release_id
      and release.completion = 'complete' and source.enabled and release.raw_removed_at is null
      and release.completed_part_count = release.expected_part_count and release.candidate_count > 0
      and artifact.evidence_sha256 = encode(sha256(convert_to(jsonb_build_object(
        'manifest', release.manifest_sha256, 'candidates', release.candidate_sha256
      )::text, 'UTF8')), 'hex')
  ) or not exists (
    select 1 from ingestion.campaign_source_artifacts pinned
    join ingestion.ingestion_runs run on run.id = pinned.ingestion_run_id
    join ingestion.sources source
      on source.source_id = run.source_id and source.resource_id = run.resource_id
    where pinned.campaign_id = p_campaign and pinned.source_id = 'acnc-register'
      and pinned.artifact_kind = 'ingestion_run' and pinned.required
      and run.completion = 'complete' and source.enabled and run.raw_removed_at is null
      and run.envelope_sha256 = pinned.evidence_sha256
      and exists (select 1 from ingestion.run_records record where record.run_id = run.id)
  ) or not exists (
    select 1 from ingestion.campaign_source_artifacts pinned
    join ingestion.registry_seed_releases release on release.id = pinned.registry_seed_release_id
    join ingestion.sources source
      on source.source_id = release.source_id and source.resource_id = release.resource_id
    where pinned.campaign_id = p_campaign
      and pinned.source_id = 'nsw-incorporated-associations'
      and pinned.artifact_kind = 'registry_seed_release' and pinned.required
      and release.completion = 'complete' and source.enabled and release.raw_removed_at is null
      and release.completed_part_count = release.expected_part_count and release.candidate_count > 0
      and pinned.evidence_sha256 = encode(sha256(convert_to(jsonb_build_object(
        'manifest', release.manifest_sha256, 'candidates', release.candidate_sha256
      )::text, 'UTF8')), 'hex')
  ) then
    raise exception 'The campaign must pin retained, unchanged and complete ABR, ACNC and NSW evidence'
      using errcode = '55000';
  end if;

  select array_agg(value::bigint order by ordinal), count(*)
    into version_ids, candidate_count
  from unnest(p_versions) with ordinality selected(value, ordinal);
  if candidate_count <> (select count(distinct value) from unnest(version_ids) value) then
    raise exception 'Campaign cohort candidate versions must be unique' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(version_ids) version_id
    where not exists (
      select 1 from ingestion.registry_seed_release_candidates candidate
      where candidate.release_id = artifact.registry_seed_release_id
        and candidate.version_id = version_id
        and candidate.in_scope
    )
  ) then
    raise exception 'Every cohort version must be an in-scope member of the pinned release'
      using errcode = '22023';
  end if;
  if exists (
    select 1 from ingestion.registry_seed_triage where version_id = any(version_ids)
  ) or exists (
    select 1 from ingestion.registry_seed_promotions
    where release_id = artifact.registry_seed_release_id and version_id = any(version_ids)
  ) then
    raise exception 'Campaign cohort must be pinned before triage or promotion' using errcode = '55000';
  end if;

  selection_hash := encode(sha256(convert_to(jsonb_build_object(
    'campaign_id', p_campaign,
    'release_id', artifact.registry_seed_release_id,
    'selection_version', btrim(p_selection_version),
    'versions', to_jsonb(version_ids)
  )::text, 'UTF8')), 'hex');

  insert into ingestion.campaign_registry_cohorts(
    campaign_id, artifact_id, release_id, selection_version, manifest_sha256,
    selection_sha256, candidate_count, reason, pinned_by
  ) values (
    campaign.campaign_id, artifact.artifact_id, artifact.registry_seed_release_id,
    btrim(p_selection_version), p_manifest_sha256, selection_hash,
    candidate_count, btrim(p_reason), auth.uid()
  );
  insert into ingestion.campaign_registry_cohort_items(campaign_id, ordinal, version_id)
  select campaign.campaign_id, ordinal::integer, value::bigint
  from unnest(p_versions) with ordinality selected(value, ordinal);

  return jsonb_build_object(
    'campaign_id', campaign.campaign_id,
    'release_id', artifact.registry_seed_release_id::text,
    'candidate_count', candidate_count,
    'selection_version', btrim(p_selection_version),
    'manifest_sha256', p_manifest_sha256,
    'selection_sha256', selection_hash
  );
end
$$;

revoke all on function community_orgs.pin_campaign_registry_cohort(
  uuid, text, text[], text, text, text
) from public, anon, service_role, ingestion_worker;
grant execute on function community_orgs.pin_campaign_registry_cohort(
  uuid, text, text[], text, text, text
) to authenticated;

create or replace function ingestion.campaign_readiness(p_campaign uuid) returns jsonb
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
  promotion_pending bigint := 0;
  field_pending bigint := 0;
  release_count bigint := 0;
  published_count bigint := 0;
  replacement jsonb;
  this_count bigint;
  campaign_has_registry boolean;
  has_cohort boolean;
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

  select exists (
    select 1 from ingestion.campaign_source_artifacts
    where campaign_id = p_campaign and artifact_kind = 'registry_seed_release'
  ) into campaign_has_registry;
  select exists (
    select 1 from ingestion.campaign_registry_cohorts where campaign_id = p_campaign
  ) into has_cohort;
  if campaign.campaign_type = 'initial_seed' and campaign_has_registry and not has_cohort then
    blockers := blockers || jsonb_build_array(jsonb_build_object(
      'code', 'campaign_cohort_missing', 'stage', 'identity',
      'message', 'Pin a bounded immutable candidate cohort before initial-seed review.',
      'responsible_role', 'data_steward'
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

      if campaign.campaign_type <> 'initial_seed' or not campaign_has_registry then
        select count(*) into this_count from ingestion.run_records where run_id = artifact.ingestion_run_id;
        record_count := record_count + this_count;
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
      end if;
    else
      select jsonb_build_object('id', r.replacement_registry_seed_release_id::text, 'recorded_at', r.recorded_at)
        into replacement from ingestion.source_artifact_replacements r
        where r.replaced_registry_seed_release_id = artifact.registry_seed_release_id;
      if artifact.required and not exists (
        select 1 from ingestion.registry_seed_releases r join ingestion.sources s using(source_id, resource_id)
        where r.id = artifact.registry_seed_release_id and r.completion = 'complete' and s.enabled
          and r.raw_removed_at is null and r.completed_part_count = r.expected_part_count
          and artifact.evidence_sha256 = encode(sha256(convert_to(jsonb_build_object(
            'manifest', r.manifest_sha256, 'candidates', r.candidate_sha256
          )::text, 'UTF8')), 'hex')
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

      if campaign.campaign_type = 'initial_seed' and exists (
        select 1 from ingestion.campaign_registry_cohorts c
        where c.campaign_id = p_campaign and c.release_id = artifact.registry_seed_release_id
      ) then
        select count(*) into this_count
        from ingestion.campaign_registry_cohort_items where campaign_id = p_campaign;
        record_count := record_count + this_count;
        select count(*) into this_count
        from ingestion.campaign_registry_cohort_items item
        left join ingestion.registry_seed_triage triage on triage.version_id = item.version_id
        where item.campaign_id = p_campaign
          and (triage.version_id is null or triage.decision = 'defer');
        identity_pending := identity_pending + this_count;
        select count(*) into this_count
        from ingestion.campaign_registry_cohort_items item
        join ingestion.registry_seed_triage triage on triage.version_id = item.version_id
          and triage.decision in ('include', 'link')
        left join ingestion.registry_seed_promotions promotion
          on promotion.release_id = artifact.registry_seed_release_id
         and promotion.version_id = item.version_id
        where item.campaign_id = p_campaign and promotion.version_id is null;
        promotion_pending := promotion_pending + this_count;
        select count(*) into this_count
        from ingestion.campaign_registry_cohort_items item
        join ingestion.registry_seed_triage triage on triage.version_id = item.version_id
          and triage.decision in ('include', 'link')
        join ingestion.registry_seed_promotions promotion
          on promotion.release_id = artifact.registry_seed_release_id
         and promotion.version_id = item.version_id
        left join ingestion.reviews review on review.version_id = promotion.staged_version_id
        where item.campaign_id = p_campaign
          and (review.version_id is null or review.decision = 'defer');
        identity_pending := identity_pending + this_count;
        select count(*) into this_count
        from ingestion.campaign_registry_cohort_items item
        join ingestion.registry_seed_promotions promotion
          on promotion.release_id = artifact.registry_seed_release_id
         and promotion.version_id = item.version_id
        join ingestion.reviews review on review.version_id = promotion.staged_version_id
          and review.decision in ('link', 'create')
        where item.campaign_id = p_campaign and not exists (
          select 1 from ingestion.change_sets changes
          where changes.run_id = promotion.run_id
            and changes.version_id = promotion.staged_version_id
            and changes.review_revision = review.revision
        );
        field_pending := field_pending + this_count;
      elsif campaign.campaign_type <> 'initial_seed' then
        select count(*) into this_count from ingestion.registry_seed_release_candidates
          where release_id = artifact.registry_seed_release_id;
        record_count := record_count + this_count;
        select count(*) into this_count from ingestion.registry_seed_release_candidates rc
          left join ingestion.registry_seed_triage t on t.version_id = rc.version_id
          where rc.release_id = artifact.registry_seed_release_id and rc.in_scope
            and (t.version_id is null or t.decision = 'defer');
        identity_pending := identity_pending + this_count;
      end if;
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
  if promotion_pending > 0 then
    blockers := blockers || jsonb_build_array(jsonb_build_object(
      'code', 'promotion_pending', 'stage', 'promotion',
      'message', format('%s included or linked cohort candidates remain in registry staging.', promotion_pending),
      'responsible_role', 'data_steward', 'count', promotion_pending
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
      'promotion_pending', promotion_pending, 'field_changes_pending', field_pending,
      'releases', release_count, 'published_releases', published_count
    ),
    'blockers', blockers
  );
end
$$;

revoke all on function ingestion.campaign_readiness(uuid)
  from public, anon, authenticated, service_role, ingestion_worker;

comment on table ingestion.campaign_registry_cohorts is
  'Immutable bounded registry candidate selection attached to an initial-seed campaign.';
comment on table ingestion.campaign_registry_cohort_items is
  'Ordered immutable candidate-version membership for a campaign registry cohort.';
comment on function community_orgs.pin_campaign_registry_cohort(uuid, text, text[], text, text, text) is
  'Pins one bounded, pre-triage ABR candidate set to an immutable initial-seed campaign.';

commit;
