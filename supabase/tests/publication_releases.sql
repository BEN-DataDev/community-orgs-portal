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
  ('00000000-0000-4000-8000-000000004301'),
  ('00000000-0000-4000-8000-000000004302'),
  ('00000000-0000-4000-8000-000000004303');
insert into portal.capability_appointments(
  user_id, capability, appointed_by, reason, approval_reference, origin
) values
  ('00000000-0000-4000-8000-000000004301', 'data_steward', null,
   'Phase 3 submitter', 'TEST-PHASE3-1', 'bootstrap'),
  ('00000000-0000-4000-8000-000000004302', 'portal_administrator', null,
   'Phase 3 approver', 'TEST-PHASE3-2', 'bootstrap'),
  ('00000000-0000-4000-8000-000000004303', 'data_steward', null,
   'Phase 3 independent steward', 'TEST-PHASE3-3', 'bootstrap');
insert into ingestion.sources(source_id, resource_id, metadata, enabled)
values ('acnc-register', 'phase3-release', '{}', true);

-- Supabase API sessions use an authenticator-derived session user, not postgres.
-- Stale direct-writer clients must fail even when the JWT has Data Steward authority.
set session authorization authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000004301","aal":"aal1"}', true);
select pg_temp.refused(
  'select community_orgs.publish_ingestion_fields(''00000000-0000-4000-8000-000000004399'')'
);
select pg_temp.refused(
  'select community_orgs.suppress_ingestion_content(''1'',''1'',''*'',''bypass'',''{}'')'
);
reset session authorization;

do $$
declare
  submitter uuid := '00000000-0000-4000-8000-000000004301';
  administrator uuid := '00000000-0000-4000-8000-000000004302';
  approver uuid := '00000000-0000-4000-8000-000000004303';
  envelope jsonb := '{"contract_version":"1.0","source_id":"acnc-register","resource_id":"phase3-release","run_id":"one","parser_version":"v1","observed_at":"2026-09-24T00:00:00Z","completion":"complete","publication_eligible":false,"scope":{},"quarantine":[],"errors":[],"records":[{"source_id":"acnc-register","resource_id":"phase3-release","run_id":"one","native_id":"1","parser_version":"v1","observed_at":"2026-09-24T00:00:00Z","raw":{},"assertions":[{"field":"entity_name","value":"Phase 3 fixture"},{"field":"website","value":"https://phase3.example"}]}]}';
  selected_run text; selected_version text; fields jsonb; change_set uuid; release uuid; org uuid;
  suppression uuid; snapshot jsonb; revised integer;
begin
  selected_run := ingestion.stage_acnc(envelope)::text;
  select rr.version_id::text into selected_version
  from ingestion.run_records rr where rr.run_id = selected_run::bigint;

  set local role authenticated;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', submitter, 'aal', 'aal1')::text, true);
  perform community_orgs.save_ingestion_review(selected_run, selected_version, 0, 'create', null, 'Phase 3 initial entity');
  select jsonb_agg(x order by x->>'field') into fields
  from jsonb_array_elements(community_orgs.ingestion_field_preview(selected_run, selected_version)->'fields') x
  where x->>'status' in ('new', 'changed');
  change_set := community_orgs.approve_ingestion_fields(selected_run, selected_version, 1, fields);
  release := community_orgs.submit_publication_release(
    'initial_seed', jsonb_build_array(jsonb_build_object(
      'action', 'publish_change_set', 'change_set_id', change_set
    )), 'Initial seed fixture'
  );
  perform pg_temp.refused(format(
    'select community_orgs.decide_publication_release(%L,1,''approved'',''Self approval'')', release
  ));
  perform pg_temp.refused(format(
    'select community_orgs.publish_publication_release(%L,1)', release
  ));

  perform set_config('request.jwt.claims', jsonb_build_object('sub', administrator, 'aal', 'aal1')::text, true);
  if community_orgs.decide_publication_release(release, 1, 'approved', 'Independent sponsor review') <> 'approved' then
    raise exception 'Independent approval was not recorded';
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', submitter, 'aal', 'aal1')::text, true);
  revised := community_orgs.revise_publication_release(
    release, 1, jsonb_build_array(jsonb_build_object(
      'action', 'publish_change_set', 'change_set_id', change_set
    )), 'Resubmitted to prove revision invalidation'
  );
  if revised <> 2 then raise exception 'Release revision was not advanced'; end if;
  perform pg_temp.refused(format(
    'select community_orgs.publish_publication_release(%L,2)', release
  ));
  perform set_config('request.jwt.claims', jsonb_build_object('sub', approver, 'aal', 'aal1')::text, true);
  perform community_orgs.decide_publication_release(release, 2, 'approved', 'Independent revised approval');
  perform set_config('request.jwt.claims', jsonb_build_object('sub', submitter, 'aal', 'aal1')::text, true);
  select (x->>'organisation_id')::uuid into org
  from jsonb_array_elements(community_orgs.publish_publication_release(release, 2)) x;
  reset role;
  if org is null or not exists(select 1 from ingestion.publications where change_set_id = change_set) then
    raise exception 'Approved release did not publish exact change set';
  end if;

  set local role authenticated;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', submitter, 'aal', 'aal1')::text, true);
  snapshot := community_orgs.ingestion_field_preview(selected_run, selected_version, org);
  suppression := community_orgs.submit_publication_release(
    'suppression', jsonb_build_array(jsonb_build_object(
      'action', 'suppress_content', 'run', selected_run, 'version', selected_version,
      'field', '*', 'reason', 'Provider withdrawal fixture',
      'expected', jsonb_build_object('organisation_id', org)
    )), 'Provider withdrawal fixture'
  );
  perform pg_temp.refused(format(
    'select community_orgs.publish_publication_release(%L,1)', suppression
  ));
  perform set_config('request.jwt.claims', jsonb_build_object('sub', approver, 'aal', 'aal1')::text, true);
  perform community_orgs.decide_publication_release(suppression, 1, 'approved', 'Independent destructive review');
  perform set_config('request.jwt.claims', jsonb_build_object('sub', submitter, 'aal', 'aal1')::text, true);
  perform community_orgs.publish_publication_release(suppression, 1);
  reset role;
  if (select is_public from community_orgs.organisations where org_id = org)
     or not exists(select 1 from ingestion.suppressions where organisation_id = org and field = '*') then
    raise exception 'Approved suppression release did not apply';
  end if;

  set local role authenticated;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', administrator, 'aal', 'aal1')::text, true);
  perform community_orgs.set_publication_approval_policy(true, 1, 'Require two people for every release');
  if not (community_orgs.publication_release_queue()->'policy'->>'ordinary_requires_independent_approval')::boolean then
    raise exception 'Updated ordinary approval policy missing';
  end if;
  reset role;

  if (select count(*) from ingestion.publication_release_decisions where release_id = release) <> 2
     or (select count(*) from ingestion.publication_release_events where release_id = release and event_type = 'published') <> 1
     or exists(select 1 from ingestion.publication_release_decisions d
       join ingestion.publication_release_revisions r using(release_id, revision)
       where d.decided_by = r.submitted_by) then
    raise exception 'Release evidence or actor separation is incomplete';
  end if;
  perform pg_temp.refused(format(
    'update ingestion.publication_release_revisions set reason=''rewritten'' where release_id=%L', release
  ));
end
$$;

rollback;

select 'Frozen release revisions, independent approval, revision invalidation and destructive dual control passed' as result;
