-- Rollback-only P28 retained-evidence redaction checks.
begin;
set local lock_timeout='3s';
set local statement_timeout='20s';
insert into ingestion.sources(source_id,resource_id,metadata,enabled)
 values('acnc-register','p28-redaction','{"synthetic":true}',true);
do $$
declare
 actor uuid := '00000000-0000-0000-0000-000000000028'::uuid;
 e jsonb := '{"contract_version":"1.0","source_id":"acnc-register","resource_id":"p28-redaction","run_id":"one","parser_version":"v1","observed_at":"2026-09-20T00:00:00Z","completion":"complete","publication_eligible":false,"scope":{},"quarantine":[],"errors":[],"records":[{"source_id":"acnc-register","resource_id":"p28-redaction","run_id":"one","native_id":"42","parser_version":"v1","observed_at":"2026-09-20T00:00:00Z","raw":{"_id":"42","Charity_Legal_Name":"P28 example","ABN":"00000000000","Charity_Website":"https://source.example"},"assertions":[{"field":"entity_name","value":"P28 example"},{"field":"abn","value":"00000000000"},{"field":"website","value":"https://source.example"}]}]}';
 r text; v text; rec bigint; org uuid; approval uuid; fields jsonb; snapshot jsonb; claims text;
 job uuid; token uuid; result jsonb;
begin
 insert into auth.users(id) values(actor) on conflict do nothing;
 insert into ingestion.operators(user_id) values(actor) on conflict do nothing;
 r:=ingestion.stage_acnc(e)::text;
 select version_id::text into v from ingestion.run_records where run_id=r::bigint;
 select record_id into rec from ingestion.source_record_versions where id=v::bigint;
 claims:=jsonb_build_object('sub',actor,'role','authenticated','aal','aal2')::text;
 perform set_config('request.jwt.claims',claims,true);
 set local role authenticated;
 perform community_orgs.save_ingestion_review(r,v,0,'create',null,'P28 redaction');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(r,v)->'fields') x
 where x->>'field' in ('entity_name','abn','website') and x->>'status' in ('new','changed');
 approval:=community_orgs.approve_ingestion_fields(r,v,1,fields);
 org:=community_orgs.publish_ingestion_fields(approval);
 select x into snapshot from jsonb_array_elements(community_orgs.ingestion_field_preview(r,v,org)->'fields') x where x->>'field'='website';
 perform community_orgs.suppress_ingestion_content(r,v,'website','Remove retained website copies',jsonb_build_object('organisation_id',org,'field',snapshot));
 reset role;

 if exists(select 1 from ingestion.field_assertions where version_id=v::bigint and field='website') then
  raise exception 'Website assertion survived suppression redaction';
 end if;
 if exists(select 1 from ingestion.source_record_versions where id=v::bigint and (payload->'raw' ? 'Charity_Website'
   or payload->'assertions' @> '[{"field":"website"}]'::jsonb)) then
  raise exception 'Version payload retained suppressed website';
 end if;
 if exists(select 1 from ingestion.ingestion_runs where id=r::bigint and envelope::text like '%source.example%') then
  raise exception 'Run envelope retained suppressed website';
 end if;
 if exists(select 1 from ingestion.change_sets c where c.id=approval and c.fields::text like '%source.example%')
  or exists(select 1 from ingestion.publications where change_set_id=approval and changes::text like '%source.example%') then
  raise exception 'Approval/publication snapshots retained suppressed website';
 end if;
 if not exists(select 1 from ingestion.retained_evidence_redaction_events where record_id=rec and field='website'
   and suppressed_by=actor and version_count=1 and assertion_count=1 and run_count=1 and approval_count=1 and publication_count=1) then
  raise exception 'Website redaction event missing';
 end if;

 -- A later staged run and a worker checkpoint for the same source identity are redacted immediately.
 e:=jsonb_set(jsonb_set(e,'{run_id}','"two"'),'{records,0,run_id}','"two"');
 e:=jsonb_set(e,'{records,0,raw,Charity_Website}','"https://later.example"');
 e:=jsonb_set(e,'{records,0,assertions,2,value}','"https://later.example"');
 set local role ingestion_worker;
 r:=ingestion.stage_acnc(e)::text;
 reset role;
 if exists(select 1 from ingestion.ingestion_runs where id=r::bigint and envelope::text like '%later.example%')
  or exists(select 1 from ingestion.source_record_versions v2 join ingestion.run_records rr on rr.version_id=v2.id
   where rr.run_id=r::bigint and v2.payload::text like '%later.example%') then
  raise exception 'Suppressed staged replay restored retained website';
 end if;

 insert into ingestion.acquisition_configs(source_id,resource_id,postcodes,licence_title,updated_by)
 values('acnc-register','p28-redaction',array['2730'],'Synthetic',actor);
 insert into ingestion.acquisition_jobs(source_id,resource_id,config_revision,source_revision,config,origin,status,
   lease_token,lease_until,attempts,created_at)
 values('acnc-register','p28-redaction',1,0,jsonb_build_object('resource_id','p28-redaction','postcodes',to_jsonb(array['2730']),
  'page_size',100,'max_pages',5,'timeout_seconds',10,'deadline_seconds',120,'max_response_bytes',2097152),'manual',
  'running',gen_random_uuid(),now()+interval '5 minutes',1,now()-interval '1 minute')
 returning id,lease_token into job,token;
 e:=jsonb_set(jsonb_set(e,'{run_id}',to_jsonb(('acnc-job-'||job::text)::text)),'{records,0,run_id}',to_jsonb(('acnc-job-'||job::text)::text));
 e:=jsonb_set(jsonb_set(e,'{observed_at}',to_jsonb(now()::text)),'{records,0,observed_at}',to_jsonb(now()::text));
 e:=jsonb_set(e,'{scope}',jsonb_build_object('kind','filtered-resource','filters',jsonb_build_object('Postcode',to_jsonb(array['2730']))));
 e:=jsonb_set(e,'{qualification}',jsonb_build_object('limits',jsonb_build_object('resource_id','p28-redaction','postcodes',to_jsonb(array['2730']),
  'page_size',100,'max_pages',5,'timeout_seconds',10,'deadline_seconds',120,'max_response_bytes',2097152)));
 e:=jsonb_set(e,'{parser_version}','"acnc-ckan-v3"');
 e:=jsonb_set(e,'{records,0,parser_version}','"acnc-ckan-v3"');
 e:=jsonb_set(e,'{synthetic}','false'::jsonb);
 e:=jsonb_set(e,'{records,0,raw,Charity_Website}','"https://checkpoint.example"');
 e:=jsonb_set(e,'{records,0,assertions,2,value}','"https://checkpoint.example"');
 set local role ingestion_worker;
 perform ingestion.checkpoint_acquisition(job,token,e);
 reset role;
 if exists(select 1 from ingestion.acquisition_jobs where id=job and checkpoint::text like '%checkpoint.example%') then
  raise exception 'Checkpoint retained suppressed website';
 end if;

 select version_id::text into v from ingestion.run_records where run_id=r::bigint;
 perform set_config('request.jwt.claims',claims,true);
 set local role authenticated;
 perform community_orgs.suppress_ingestion_content(r,v,'*',
  'Whole record withdrawal',jsonb_build_object('organisation_id',org));
 reset role;
 if exists(select 1 from ingestion.source_record_versions where record_id=rec and payload::text like '%P28 example%')
  or exists(select 1 from ingestion.ingestion_runs where source_id='acnc-register' and resource_id='p28-redaction'
   and envelope::text like '%P28 example%') then
  raise exception 'Whole-record withdrawal retained source name';
 end if;
 if exists(select 1 from ingestion.field_assertions f join ingestion.source_record_versions v3 on v3.id=f.version_id
   where v3.record_id=rec) then
  raise exception 'Whole-record withdrawal retained assertions';
 end if;
 if (select is_public from community_orgs.organisations where org_id=org) then
  raise exception 'Whole-record withdrawal did not hide target';
 end if;
 result:=jsonb_build_object('events',(select count(*) from ingestion.retained_evidence_redaction_events where record_id=rec));
 perform set_config('test.p28_redaction_result','Retained suppression redaction removed versions, runs, checkpoints, approvals, publications and replay copies: '||result::text,true);
end $$;
select current_setting('test.p28_redaction_result') as result;
rollback;
