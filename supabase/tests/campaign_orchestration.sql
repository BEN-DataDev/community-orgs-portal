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
  ('00000000-0000-4000-8000-000000004401'),
  ('00000000-0000-4000-8000-000000004402');
insert into portal.capability_appointments(
  user_id, capability, appointed_by, reason, approval_reference, origin
) values
  ('00000000-0000-4000-8000-000000004401', 'data_steward', null,
   'Phase 4 campaign steward', 'TEST-PHASE4-1', 'bootstrap'),
  ('00000000-0000-4000-8000-000000004402', 'portal_administrator', null,
   'Phase 4 campaign administrator', 'TEST-PHASE4-2', 'bootstrap');
insert into ingestion.sources(source_id, resource_id, metadata, enabled)
values ('acnc-register', 'phase4-campaign', '{}', true);

do $$
declare
  steward uuid := '00000000-0000-4000-8000-000000004401';
  administrator uuid := '00000000-0000-4000-8000-000000004402';
  scope_id text;
  first_run text;
  replacement_run text;
  campaign uuid;
  sibling uuid;
  release uuid;
  before_campaign jsonb;
  after_campaign jsonb;
  readiness jsonb;
  kind text;
begin
  select current_scope_revision_id::text into scope_id
  from portal.configuration where singleton;
  if scope_id is null then raise exception 'Campaign test requires configured portal scope'; end if;

  first_run := ingestion.stage_acnc(jsonb_build_object(
    'contract_version', '1.0', 'source_id', 'acnc-register',
    'resource_id', 'phase4-campaign', 'run_id', 'phase4-original',
    'parser_version', 'phase4-parser-v1', 'observed_at', '2026-09-25T00:00:00Z',
    'completion', 'complete', 'publication_eligible', false,
    'scope', '{}'::jsonb, 'quarantine', '[]'::jsonb, 'errors', '[]'::jsonb,
    'records', '[]'::jsonb
  ))::text;
  replacement_run := ingestion.stage_acnc(jsonb_build_object(
    'contract_version', '1.0', 'source_id', 'acnc-register',
    'resource_id', 'phase4-campaign', 'run_id', 'phase4-replacement',
    'parser_version', 'phase4-parser-v2', 'observed_at', '2026-09-25T01:00:00Z',
    'completion', 'complete', 'publication_eligible', false,
    'scope', '{}'::jsonb, 'quarantine', '[]'::jsonb, 'errors', '[]'::jsonb,
    'records', '[]'::jsonb
  ))::text;

  set local role authenticated;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', steward, 'aal', 'aal1')::text, true);
  campaign := community_orgs.create_campaign(
    'initial_seed', 'Phase 4 immutable readiness fixture', scope_id,
    '{"identity":"identity-v1","fields":"fields-v1"}',
    jsonb_build_array(jsonb_build_object(
      'kind', 'ingestion_run', 'id', first_run, 'purpose', 'Primary ACNC snapshot', 'required', true
    )), 'Prove campaign source replacement invalidation'
  );
  readiness := community_orgs.campaign_readiness(campaign);
  if not (readiness->>'ready')::boolean or readiness->>'state' <> 'ready_for_release' then
    raise exception 'Complete empty source fixture should initially be ready: %', readiness;
  end if;
  reset role;

  select to_jsonb(c) into before_campaign from portal.campaigns c where campaign_id = campaign;

  set local role authenticated;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', steward, 'aal', 'aal1')::text, true);
  perform community_orgs.record_source_artifact_replacement(
    'ingestion_run', first_run, replacement_run, 'Provider replaced the source artifact'
  );
  readiness := community_orgs.campaign_readiness(campaign);
  if (readiness->>'ready')::boolean
     or not (readiness->'blockers' @> '[{"code":"source_artifact_replaced"}]'::jsonb) then
    raise exception 'Replacement did not invalidate campaign readiness: %', readiness;
  end if;
  reset role;

  select to_jsonb(c) into after_campaign from portal.campaigns c where campaign_id = campaign;
  if after_campaign is distinct from before_campaign then
    raise exception 'Source replacement mutated the prior campaign';
  end if;

  -- Every required Phase 4 campaign kind uses the same immutable contract.
  foreach kind in array array[
    'scheduled_refresh', 'scope_rebaseline', 'correction', 'withdrawal', 'source_reprocessing'
  ] loop
    set local role authenticated;
    perform set_config('request.jwt.claims', jsonb_build_object('sub', steward, 'aal', 'aal1')::text, true);
    sibling := community_orgs.create_campaign(
      kind, 'Phase 4 ' || replace(kind, '_', ' '), scope_id,
      '{"identity":"identity-v1","fields":"fields-v1"}',
      jsonb_build_array(jsonb_build_object(
        'kind', 'ingestion_run', 'id', replacement_run, 'purpose', 'Replacement source', 'required', true
      )), 'Exercise the complete campaign type contract', null, campaign
    );
    reset role;
  end loop;

  insert into ingestion.publication_releases(release_class, status, created_by)
  values ('ordinary_update', 'submitted', steward) returning release_id into release;
  set local role authenticated;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', administrator, 'aal', 'aal1')::text, true);
  if community_orgs.link_campaign_publication_release(sibling, release) is distinct from true then
    raise exception 'Publication release was not linked to campaign';
  end if;
  if jsonb_array_length(community_orgs.campaign_dashboard()->'campaigns') < 6 then
    raise exception 'Campaign dashboard omitted campaign records';
  end if;
  reset role;

  perform pg_temp.refused(format(
    'update portal.campaigns set name=''rewritten'' where campaign_id=%L', campaign
  ));
  perform pg_temp.refused(format(
    'delete from ingestion.campaign_source_artifacts where campaign_id=%L', campaign
  ));
end
$$;

rollback;

select 'Immutable campaigns, source replacement invalidation, release links and dashboard passed' as result;
