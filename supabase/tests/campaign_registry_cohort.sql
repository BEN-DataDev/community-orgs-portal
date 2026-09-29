begin;

create function pg_temp.refused(command text) returns void language plpgsql as $$
begin
  begin execute command;
  exception when others then return;
  end;
  raise exception 'Unexpected success: %', command;
end
$$;

insert into auth.users(id) values ('00000000-0000-4000-8000-000000004451');
insert into portal.capability_appointments(
  user_id, capability, appointed_by, reason, approval_reference, origin
) values (
  '00000000-0000-4000-8000-000000004451', 'data_steward', null,
  'Campaign cohort steward', 'TEST-COHORT-1', 'bootstrap'
);

update ingestion.sources set enabled = true
where source_id in ('abr-bulk', 'nsw-incorporated-associations');
insert into ingestion.sources(source_id, resource_id, metadata, enabled)
values ('acnc-register', 'campaign-cohort-acnc', '{}', true);

do $$
declare
  steward uuid := '00000000-0000-4000-8000-000000004451';
  scope_id text;
  acnc_run bigint;
  acnc_record bigint;
  acnc_version bigint;
  abr_release bigint;
  nsw_release bigint;
  abr_candidate_one bigint;
  abr_candidate_two bigint;
  abr_version_one bigint;
  abr_version_two bigint;
  nsw_candidate bigint;
  nsw_version bigint;
  campaign uuid;
  replacement_campaign uuid;
  pinned jsonb;
  readiness jsonb;
  promoted_run text;
begin
  select current_scope_revision_id::text into strict scope_id
  from portal.configuration where singleton;

  insert into ingestion.ingestion_runs(
    source_id, resource_id, run_key, completion, observed_at, envelope
  ) values (
    'acnc-register', 'campaign-cohort-acnc', 'campaign-cohort-acnc-run', 'complete',
    '2026-09-29T00:00:00Z',
    '{"contract_version":"1.0","source_id":"acnc-register","resource_id":"campaign-cohort-acnc","run_id":"campaign-cohort-acnc-run","parser_version":"test-v1","mapping_version":"test-v1","observed_at":"2026-09-29T00:00:00Z","completion":"complete","publication_eligible":false,"scope":{},"records":[],"quarantine":[],"errors":[]}'::jsonb
  ) returning id into acnc_run;
  insert into ingestion.source_records(source_id, resource_id, native_id)
  values ('acnc-register', 'campaign-cohort-acnc', 'cohort-acnc-1')
  returning id into acnc_record;
  insert into ingestion.source_record_versions(record_id, parser_version, content_hash, payload)
  values (acnc_record, 'test-v1', repeat('1', 64), '{"raw":{},"assertions":[]}'::jsonb)
  returning id into acnc_version;
  insert into ingestion.run_records(run_id, version_id) values (acnc_run, acnc_version);

  insert into ingestion.registry_seed_releases(
    source_id, resource_id, release_key, parser_version, observed_at, completion,
    scope, manifest, manifest_sha256, candidate_sha256,
    expected_part_count, completed_part_count, candidate_count, retention_policy
  ) values (
    'abr-bulk', '5bd7fcab-e315-42cb-8daf-50b7efc2027e', 'campaign-cohort-abr',
    'test-v1', '2026-09-29T00:00:00Z', 'complete',
    '{"kind":"configured-registry-scope","complete_snapshot":true,"selection":{},"snapshot_series":"campaign-cohort-abr"}',
    '{}', repeat('2', 64), repeat('3', 64), 1, 1, 2,
    '{"class":"hold","basis":"campaign cohort regression"}'
  ) returning id into abr_release;
  insert into ingestion.registry_seed_release_parts(
    release_id, part_key, ordinal, status, observed_sha256, record_count
  ) values (abr_release, 'part-1', 1, 'complete', repeat('4', 64), 2);

  insert into ingestion.registry_seed_candidates(source_id, resource_id, native_id)
  values ('abr-bulk', '5bd7fcab-e315-42cb-8daf-50b7efc2027e', '11111111111')
  returning id into abr_candidate_one;
  insert into ingestion.registry_seed_candidates(source_id, resource_id, native_id)
  values ('abr-bulk', '5bd7fcab-e315-42cb-8daf-50b7efc2027e', '22222222222')
  returning id into abr_candidate_two;
  insert into ingestion.registry_seed_candidate_versions(candidate_id, parser_version, content_hash, payload)
  values (abr_candidate_one, 'test-v1', repeat('5', 64),
    '{"raw":{},"assertions":[{"field":"entity_name","value":"Cohort excluded fixture"}]}'::jsonb)
  returning id into abr_version_one;
  insert into ingestion.registry_seed_candidate_versions(candidate_id, parser_version, content_hash, payload)
  values (abr_candidate_two, 'test-v1', repeat('6', 64),
    '{"raw":{},"assertions":[{"field":"entity_name","value":"Cohort included fixture"}]}'::jsonb)
  returning id into abr_version_two;
  insert into ingestion.registry_seed_release_candidates(release_id, version_id, in_scope, selection_reasons)
  values
    (abr_release, abr_version_one, true, '["test"]'),
    (abr_release, abr_version_two, true, '["test"]');

  insert into ingestion.registry_seed_releases(
    source_id, resource_id, release_key, parser_version, observed_at, completion,
    scope, manifest, manifest_sha256, candidate_sha256,
    expected_part_count, completed_part_count, candidate_count, retention_policy
  ) values (
    'nsw-incorporated-associations', 'public-register-search', 'campaign-cohort-nsw',
    'test-v1', '2026-09-29T00:00:00Z', 'complete',
    '{"kind":"configured-registry-scope","complete_snapshot":true,"selection":{},"snapshot_series":"campaign-cohort-nsw"}',
    '{}', repeat('7', 64), repeat('8', 64), 1, 1, 1,
    '{"class":"hold","basis":"campaign cohort regression"}'
  ) returning id into nsw_release;
  insert into ingestion.registry_seed_release_parts(
    release_id, part_key, ordinal, status, observed_sha256, record_count
  ) values (nsw_release, 'part-1', 1, 'complete', repeat('9', 64), 1);
  insert into ingestion.registry_seed_candidates(source_id, resource_id, native_id)
  values ('nsw-incorporated-associations', 'public-register-search', 'INC0000001')
  returning id into nsw_candidate;
  insert into ingestion.registry_seed_candidate_versions(candidate_id, parser_version, content_hash, payload)
  values (nsw_candidate, 'test-v1', repeat('a', 64),
    '{"raw":{},"assertions":[{"field":"entity_name","value":"NSW evidence fixture"}]}'::jsonb)
  returning id into nsw_version;
  insert into ingestion.registry_seed_release_candidates(release_id, version_id, in_scope, selection_reasons)
  values (nsw_release, nsw_version, true, '["test"]');

  set local role authenticated;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', steward, 'aal', 'aal1')::text, true);
  campaign := community_orgs.create_campaign(
    'initial_seed', 'Bounded campaign cohort fixture', scope_id,
    '{"identity":"cohort-v1","fields":"cohort-v1"}',
    jsonb_build_array(
      jsonb_build_object('kind', 'registry_seed_release', 'id', abr_release, 'purpose', 'ABR candidates'),
      jsonb_build_object('kind', 'ingestion_run', 'id', acnc_run, 'purpose', 'ACNC evidence'),
      jsonb_build_object('kind', 'registry_seed_release', 'id', nsw_release, 'purpose', 'NSW evidence')
    ), 'Prove bounded immutable campaign readiness'
  );
  readiness := community_orgs.campaign_readiness(campaign);
  if readiness->'counts'->>'records' <> '0'
     or not (readiness->'blockers' @> '[{"code":"campaign_cohort_missing"}]') then
    raise exception 'Initial seed did not require a bounded cohort: %', readiness;
  end if;
  reset role;

  set local role service_role;
  perform pg_temp.refused(format(
    'select community_orgs.pin_campaign_registry_cohort(%L,%L,array[%L,%L],''cohort-v1'',%L,''test'')',
    campaign, abr_release, abr_version_one, abr_version_two, repeat('b', 64)
  ));
  reset role;

  set local role authenticated;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', steward, 'aal', 'aal1')::text, true);
  pinned := community_orgs.pin_campaign_registry_cohort(
    campaign, abr_release::text, array[abr_version_one::text, abr_version_two::text],
    'cohort-v1', repeat('b', 64), 'Bound the first review cohort'
  );
  if pinned->>'candidate_count' <> '2' then raise exception 'Unexpected pin result: %', pinned; end if;
  readiness := community_orgs.campaign_readiness(campaign);
  if readiness->'counts'->>'records' <> '2'
     or readiness->'counts'->>'identity_pending' <> '2'
     or readiness->'counts'->>'promotion_pending' <> '0'
     or readiness->'blockers' @> '[{"code":"campaign_cohort_missing"}]' then
    raise exception 'Readiness did not narrow to the cohort: %', readiness;
  end if;
  perform pg_temp.refused(format(
    'select community_orgs.pin_campaign_registry_cohort(%L,%L,array[%L,%L],''cohort-v2'',%L,''duplicate'')',
    campaign, abr_release, abr_version_one, abr_version_two, repeat('c', 64)
  ));
  perform community_orgs.save_registry_seed_triage(
    abr_version_one::text, 0, 'exclude', null, null, 'Outside the fixture inclusion policy'
  );
  perform community_orgs.save_registry_seed_triage(
    abr_version_two::text, 0, 'include', null, null, 'Inside the fixture inclusion policy'
  );
  readiness := community_orgs.campaign_readiness(campaign);
  if readiness->'counts'->>'identity_pending' <> '0'
     or readiness->'counts'->>'promotion_pending' <> '1'
     or not (readiness->'blockers' @> '[{"code":"promotion_pending","count":1}]') then
    raise exception 'Triage readiness was not cohort-scoped: %', readiness;
  end if;
  promoted_run := community_orgs.promote_registry_seed_candidates(
    abr_release::text, array[abr_version_two::text], 'Promote the included cohort fixture'
  );
  readiness := community_orgs.campaign_readiness(campaign);
  if readiness->'counts'->>'identity_pending' <> '1'
     or readiness->'counts'->>'promotion_pending' <> '0' then
    raise exception 'Promoted cohort did not enter ordinary identity review: %', readiness;
  end if;
  replacement_campaign := community_orgs.create_campaign(
    'initial_seed', 'Replacement bounded campaign cohort fixture', scope_id,
    '{"identity":"cohort-v2","fields":"cohort-v2"}',
    jsonb_build_array(
      jsonb_build_object('kind', 'registry_seed_release', 'id', abr_release, 'purpose', 'ABR candidates'),
      jsonb_build_object('kind', 'ingestion_run', 'id', acnc_run, 'purpose', 'ACNC evidence'),
      jsonb_build_object('kind', 'registry_seed_release', 'id', nsw_release, 'purpose', 'NSW evidence')
    ), 'Replace a cohort whose geographic eligibility was not established', null, campaign
  );
  readiness := community_orgs.campaign_readiness(campaign);
  if readiness->>'ready' <> 'false'
     or not (readiness->'blockers' @> jsonb_build_array(jsonb_build_object(
       'code', 'campaign_superseded', 'replacement_campaign_id', replacement_campaign
     ))) then
    raise exception 'Superseded campaign was not permanently blocked: %', readiness;
  end if;
  reset role;

  perform pg_temp.refused(format(
    'update ingestion.campaign_registry_cohorts set reason=''rewritten'' where campaign_id=%L', campaign
  ));
  perform pg_temp.refused(format(
    'delete from ingestion.campaign_registry_cohort_items where campaign_id=%L', campaign
  ));
end
$$;

rollback;

select 'Immutable bounded campaign cohort and cohort-scoped readiness passed' as result;
