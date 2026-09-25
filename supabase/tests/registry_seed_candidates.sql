-- P31 rollback-only regression. Run after all migrations with ingestion_bootstrap.sql.
begin;
create or replace function community_orgs.is_platform_admin() returns boolean language sql as $$
 select coalesce(auth.jwt()->>'test_admin','false')='true' $$;

insert into auth.users(id) values
 ('00000000-0000-4000-8000-000000003101'),
 ('00000000-0000-4000-8000-000000003102');
insert into ingestion.operators(user_id) values ('00000000-0000-4000-8000-000000003101');
insert into ingestion.sources(source_id,resource_id,metadata,enabled) values
 ('abr-bulk','p31-fixture','{"synthetic":true}',true);

do $$
declare
 manifest jsonb := '{
  "contract_version":"registry-seed-v1","source_id":"abr-bulk","resource_id":"p31-fixture",
  "release_id":"2026-09-21","parser_version":"abr-xml-v1","observed_at":"2026-09-21T00:00:00Z",
  "completion":"complete","scope":{"kind":"configured-registry-scope","complete_snapshot":true,
   "snapshot_series":"abr-weekly-snowy-valleys","selection":{"postcodes":["2720","2730"],"known_abns":[]}},
  "parts":[
   {"part_id":"part-1.xml","ordinal":1,"status":"complete","expected_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","record_count":2},
   {"part_id":"part-2.xml","ordinal":2,"status":"complete","expected_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","record_count":1}],
  "errors":[],"retention":{"class":"hold","basis":"P31 fixture hold pending reviewed promotion"}}';
 candidates jsonb := '[
  {"source_id":"abr-bulk","resource_id":"p31-fixture","release_id":"2026-09-21","parser_version":"abr-xml-v1","observed_at":"2026-09-21T00:00:00Z","native_id":"51824753556","raw":{"ABN":"51824753556","name":"Included Association"},"assertions":[{"field":"entity_name","value":"Included Association"},{"field":"abn","value":"51824753556"}],"selection":{"in_scope":true,"reasons":["registered postcode 2730"]}},
  {"source_id":"abr-bulk","resource_id":"p31-fixture","release_id":"2026-09-21","parser_version":"abr-xml-v1","observed_at":"2026-09-21T00:00:00Z","native_id":"11000000000","raw":{"ABN":"11000000000","name":"Adjacent Association"},"assertions":[{"field":"entity_name","value":"Adjacent Association"},{"field":"abn","value":"11000000000"}],"selection":{"in_scope":false,"reasons":["adjacent-area evidence only"]}}]';
 v_release bigint; replay bigint; included_version bigint; adjacent_version bigint; staged_run text;
 partial_manifest jsonb; partial_release bigint; expired_manifest jsonb; expired_release bigint;
 expired_candidates jsonb; before_orgs bigint; result jsonb;
 chunk_manifest jsonb; chunk_candidates jsonb; upload bigint; chunk_release bigint; cleared integer;
begin
 if has_table_privilege('anon','ingestion.registry_seed_candidates','SELECT')
  or has_table_privilege('authenticated','ingestion.registry_seed_releases','SELECT')
  or has_table_privilege('ingestion_worker','ingestion.registry_seed_candidates','INSERT')
  or has_function_privilege('authenticated','ingestion.stage_registry_seed(jsonb,jsonb)','EXECUTE')
  or has_function_privilege('ingestion_worker','community_orgs.promote_registry_seed_candidates(text,text[],text)','EXECUTE') then
  raise exception 'Unexpected registry seed privileges';
 end if;

 set local role ingestion_worker;
 v_release:=ingestion.stage_registry_seed(manifest,candidates);
 replay:=ingestion.stage_registry_seed(manifest,candidates);
 reset role;
 if replay<>v_release or (select count(*) from ingestion.registry_seed_releases where id=v_release)<>1
  or (select count(*) from ingestion.registry_seed_release_parts where registry_seed_release_parts.release_id=v_release)<>2
  or (select count(*) from ingestion.registry_seed_release_candidates where registry_seed_release_candidates.release_id=v_release)<>2 then
  raise exception 'Release replay or inventory invariant failed'; end if;
 set local role ingestion_worker;
 begin
  perform ingestion.stage_registry_seed(manifest,jsonb_set(candidates,'{0,raw,name}','"Changed replay"'));
  raise exception 'Changed release replay accepted';
 exception when unique_violation then null; end;
 reset role;

 chunk_manifest:=jsonb_set(manifest,'{release_id}','"2026-09-21-chunked"');
 select jsonb_agg(jsonb_set(value,'{release_id}','"2026-09-21-chunked"') order by ordinality)
  into chunk_candidates from jsonb_array_elements(candidates) with ordinality;
 set local role ingestion_worker;
 select upload_id into upload from ingestion.begin_registry_seed_upload(chunk_manifest,2);
 if ingestion.append_registry_seed_upload(upload,0,jsonb_build_array(chunk_candidates->0))<>1
  or ingestion.append_registry_seed_upload(upload,0,jsonb_build_array(chunk_candidates->0))<>1
  or ingestion.append_registry_seed_upload(upload,1,jsonb_build_array(chunk_candidates->1))<>2 then
  raise exception 'Chunked upload append/replay count failed'; end if;
 begin
  perform ingestion.append_registry_seed_upload(upload,0,
   jsonb_build_array(jsonb_set(chunk_candidates->0,'{raw,name}','"Changed chunk"')));
  raise exception 'Changed chunk replay accepted';
 exception when unique_violation then null; end;
 chunk_release:=ingestion.finalize_registry_seed_upload(upload);
 if ingestion.finalize_registry_seed_upload(upload)<>chunk_release then
  raise exception 'Chunked finalization replay changed release'; end if;
 cleared:=ingestion.clear_finalized_registry_seed_upload(upload);
 reset role;
 if cleared<>2
  or exists(select 1 from ingestion.registry_seed_upload_candidates where upload_id=upload)
  or not exists(select 1 from ingestion.registry_seed_uploads
    where id=upload and status='finalized' and release_id=chunk_release
     and received_candidate_count=2)
  or (select candidate_count from ingestion.registry_seed_releases where id=chunk_release)<>2
  or (select count(*) from ingestion.registry_seed_release_candidates where release_id=chunk_release)<>2 then
  raise exception 'Chunked finalization or cleanup invariant failed'; end if;

 select cv.id into included_version from ingestion.registry_seed_candidate_versions cv
  join ingestion.registry_seed_candidates c on c.id=cv.candidate_id where c.native_id='51824753556';
 select cv.id into adjacent_version from ingestion.registry_seed_candidate_versions cv
  join ingestion.registry_seed_candidates c on c.id=cv.candidate_id where c.native_id='11000000000';
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000003101","aal":"aal2"}',true);
 set local role authenticated;
 perform community_orgs.save_registry_seed_triage(included_version::text,0,'include',null,null,
  'Postcode is configured; send this bounded candidate to ordinary reviewed staging');
 perform community_orgs.save_registry_seed_triage(adjacent_version::text,0,'exclude',null,null,
  'Adjacent address alone is outside the configured publication cohort');
 begin
  perform community_orgs.save_registry_seed_triage(included_version::text,0,'defer',null,null,'Stale revision');
  raise exception 'Stale triage revision accepted';
 exception when serialization_failure then null; end;
 result:=community_orgs.registry_seed_triage_queue(
  v_release::text,included_version::text,'all',0);
 if result->>'release_id'<>v_release::text or result->>'total'<>'2'
  or result#>>'{detail,version_id}'<>included_version::text
  or result#>>'{detail,triage,decision}'<>'include'
  or (result#>'{detail,payload}') ? 'raw'
  or jsonb_array_length(result->'records')<>2 then
  raise exception 'Redacted registry seed triage queue failed: %',result; end if;
 select count(*) into before_orgs from community_orgs.organisations;
 staged_run:=community_orgs.promote_registry_seed_candidates(v_release::text,array[included_version::text],
  'Bounded P31 promotion fixture');
 if (select count(*) from community_orgs.organisations)<>before_orgs then
  raise exception 'Candidate promotion created a public organisation'; end if;
 reset role;
 if not exists(select 1 from ingestion.registry_seed_promotions p where p.release_id=v_release
   and p.version_id=included_version and p.run_id=staged_run::bigint)
  or not exists(select 1 from ingestion.run_records where run_id=staged_run::bigint)
  or not exists(select 1 from ingestion.field_assertions a join ingestion.run_records rr on rr.version_id=a.version_id
    where rr.run_id=staged_run::bigint and a.field='abn' and a.value='"51824753556"') then
  raise exception 'Promotion did not reach existing private staging'; end if;
 set local role authenticated;
 begin
  perform community_orgs.promote_registry_seed_candidates(v_release::text,array[adjacent_version::text],
   'Must reject excluded and out-of-scope candidate');
  raise exception 'Out-of-scope candidate promotion accepted';
 exception when invalid_parameter_value then null; end;
 reset role;

 partial_manifest:=jsonb_set(manifest,'{release_id}','"2026-09-28-partial"');
 partial_manifest:=jsonb_set(partial_manifest,'{completion}','"partial"');
 partial_manifest:=jsonb_set(partial_manifest,'{scope,complete_snapshot}','false');
 partial_manifest:=jsonb_set(partial_manifest,'{parts,1,status}','"failed"');
 partial_manifest:=partial_manifest #- '{parts,1,sha256}' #- '{parts,1,record_count}';
 partial_manifest:=jsonb_set(partial_manifest,'{errors}','[{"part_id":"part-2.xml","message":"fixture failure"}]');
 set local role ingestion_worker;
 partial_release:=ingestion.stage_registry_seed(partial_manifest,'[]');
 reset role;
 update ingestion.registry_seed_triage set decision='include' where version_id=included_version;
 set local role authenticated;
 begin
  perform community_orgs.promote_registry_seed_candidates(partial_release::text,array[included_version::text],
   'Must reject partial release');
  raise exception 'Partial release promotion accepted';
 exception when invalid_parameter_value then null; end;
 reset role;

 expired_manifest:=jsonb_set(manifest,'{release_id}','"2026-10-05-expiring"');
 expired_manifest:=jsonb_set(expired_manifest,'{retention}',
  '{"class":"scheduled","basis":"Synthetic expiry coverage","raw_expires_at":"2027-01-01T00:00:00Z"}');
 expired_manifest:=jsonb_set(expired_manifest,'{parts,0,sha256}','"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"');
 expired_manifest:=jsonb_set(expired_manifest,'{parts,0,expected_sha256}','"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"');
 expired_candidates:=jsonb_build_array(jsonb_set(jsonb_set(candidates->0,'{release_id}',
  '"2026-10-05-expiring"'),'{native_id}','"22000000000"'));
 set local role ingestion_worker;
 expired_release:=ingestion.stage_registry_seed(expired_manifest,expired_candidates);
 reset role;
 update ingestion.registry_seed_releases set retention_policy=jsonb_set(retention_policy,'{raw_expires_at}','"2026-01-01T00:00:00Z"')
  where id=expired_release;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000003102","aal":"aal2","test_admin":true}',true);
 set local role authenticated;
 result:=community_orgs.expire_registry_seed_raw(expired_release::text,true);
 reset role;
 if result->>'applied'<>'true' or result->>'versions'<>'1'
  or not exists(select 1 from ingestion.registry_seed_releases
   where id=expired_release and raw_removed_at is not null)
  or not exists(select 1 from ingestion.registry_seed_release_candidates rc
   join ingestion.registry_seed_candidate_versions cv on cv.id=rc.version_id
   where rc.release_id=expired_release and cv.raw_removed_at is not null
    and cv.payload->'raw_evidence_removed'='true'::jsonb and not cv.payload ? 'raw')
  or not exists(select 1 from ingestion.registry_seed_retention_events where release_id=expired_release and applied) then
  raise exception 'Audited candidate retention expiry failed: %',result; end if;

 if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='ingestion' and c.relname like 'registry_seed%' and c.relkind='r' and not c.relrowsecurity) then
  raise exception 'Registry seed table missing RLS'; end if;
 raise notice 'P31 registry seed contract, completeness, triage, promotion and retention passed';
end $$;
rollback;
