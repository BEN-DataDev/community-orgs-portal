-- Run after the P34a migration. Synthetic validation evidence rolls back.
begin;
insert into auth.users(id) values
 ('00000000-0000-4000-8000-000000000341'),
 ('00000000-0000-4000-8000-000000000342');
insert into ingestion.operators(user_id) values ('00000000-0000-4000-8000-000000000341');
insert into ingestion.sources(source_id,resource_id,metadata,enabled)
 values('acnc-register','p34a-fixture','{}',true);

do $$
declare
 parent_envelope jsonb := $json${
  "contract_version":"1.0","source_id":"acnc-register","resource_id":"p34a-fixture",
  "run_id":"p34a-parent","parser_version":"acnc-ckan-v3","observed_at":"2026-09-23T00:00:00Z",
  "completion":"partial","publication_eligible":false,"scope":{"kind":"bounded","complete_snapshot":false},
  "pages":[],"errors":[],"records":[],
  "quarantine":[{"row":0,"native_id":"2","reason":"Charity_Website: expected HTTP(S) URL","raw_sha256":"6729e6f626d11ebd226eccf60cbaef2bdcde42eb0a334acf1cf607cc18b1a0b7","raw":{"_id":"2","Charity_Legal_Name":"P34a fixture","Charity_Website":"example.org/path"}}],
  "issues":[{"subject":{"native_id":"2","row":0},"field":{"source_key":"Charity_Website","canonical_key":"website"},"code":"website.format","category":"field_format","severity":"blocking","source_value":"example.org/path","raw_evidence_hash":"1113359608879692bdb65ab2b0d5b9c822717b702c09099165ab9895251c16ec","validator":{"name":"http_url","version":"acnc-ckan-v3"},"allowed_resolutions":["correct","omit","defer","reject_record"],"detail":"Charity_Website: expected HTTP(S) URL"}],
  "counts":{"accepted":0,"quarantined":1,"pages":0,"source_total":1}
 }$json$;
 derived_envelope jsonb; parent bigint; issue text; replay text; claimed jsonb; derived bigint;
 q jsonb; before_orgs bigint;
begin
 select count(*) into before_orgs from community_orgs.organisations;
 if has_table_privilege('authenticated','ingestion.validation_issues','SELECT')
  or has_table_privilege('service_role','ingestion.validation_resolutions','SELECT')
  or has_function_privilege('anon','community_orgs.validation_issue_queue(text,text,text,text,text,integer)','EXECUTE')
  or has_function_privilege('authenticated','ingestion.claim_validation_replay()','EXECUTE') then
  raise exception 'Validation evidence grants are too broad'; end if;

 set local role ingestion_worker;
 parent:=ingestion.stage_acnc(parent_envelope);
 reset role;
 select id::text into issue from ingestion.validation_issues where ingestion_run_id=parent;
 if issue is null or (select count(*) from ingestion.validation_issues where ingestion_run_id=parent)<>1 then
  raise exception 'Structured issue was not materialised exactly once'; end if;
 set local role ingestion_worker;
 if ingestion.stage_acnc(parent_envelope)<>parent then raise exception 'Idempotent stage changed run'; end if;
 reset role;
 if (select count(*) from ingestion.validation_issues where ingestion_run_id=parent)<>1 then
  raise exception 'Idempotent stage duplicated issue'; end if;

 set local role authenticated;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000342","aal":"aal2"}',true);
 begin perform community_orgs.validation_issue_queue(); raise exception 'Expected non-operator denial';
 exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000341","aal":"aal2"}',true);
 q:=community_orgs.validation_issue_queue(issue,parent::text,null,'field_format','',0);
 if q->>'total'<>'1' or q->'detail'->>'code'<>'website.format'
  or q->'counts'->>'unresolved'<>'1' then raise exception 'Issue queue omitted structured evidence'; end if;
 if (community_orgs.validate_issue_value(issue,'"https://example.org/path"')->>'valid')::boolean is distinct from true
  or (community_orgs.validate_issue_value(issue,'"javascript:alert(1)"')->>'valid')::boolean is distinct from false then
  raise exception 'Authoritative URL validation failed'; end if;
 perform community_orgs.save_validation_resolution(issue,0,'correct','"https://example.org/path"','Checked against source website',null);
 begin perform community_orgs.save_validation_resolution(issue,0,'omit',null,'Stale decision',null);
  raise exception 'Expected stale resolution rejection'; exception when serialization_failure then null; end;
 reset role;
 if (select count(*) from ingestion.validation_resolution_events where issue_id=issue::bigint)<>1
  or (select count(*) from ingestion.validation_attempts where issue_id=issue::bigint)<>2 then
  raise exception 'Validation audit history missing'; end if;
 set local role authenticated;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000341","aal":"aal2"}',true);
 replay:=community_orgs.create_corrected_run(parent::text);
 begin perform community_orgs.create_corrected_run(parent::text); raise exception 'Expected duplicate replay rejection';
 exception when serialization_failure then null; end;
 reset role;

 set local role ingestion_worker;
 claimed:=ingestion.claim_validation_replay();
 if claimed->>'id' is distinct from replay then raise exception 'Replay claim mismatch'; end if;
 reset role;
 derived_envelope:=parent_envelope||jsonb_build_object(
  'run_id','validation-replay-'||replay,'completion','complete','quarantine','[]'::jsonb,'issues','[]'::jsonb,
  'mapping_version','acnc-register-fields-v3','counts',jsonb_build_object('accepted',1,'quarantined',0,'pages',0,'source_total',1),
  'validation_replay',jsonb_build_object('id',replay,'parent_run_id',parent),
  'records',jsonb_build_array(jsonb_build_object(
   'source_id','acnc-register','resource_id','p34a-fixture','run_id','validation-replay-'||replay,
   'native_id','2','parser_version','acnc-ckan-v3','observed_at','2026-09-23T00:00:00Z',
   'source_modified_at',null,'source_url','https://data.gov.au/fixture',
   'raw',jsonb_build_object('_id','2','Charity_Legal_Name','P34a fixture','Charity_Website','https://example.org/path'),
   'raw_sha256','7cc23f7896e5db934786236debc64f9f93372b2a4ea3400ed39c50b53e058c17',
   'mapping_version','acnc-register-fields-v3','warnings','[]'::jsonb,
   'assertions',jsonb_build_array(
    jsonb_build_object('field','entity_name','value','P34a fixture'),
    jsonb_build_object('field','website','value','https://example.org/path')))));
 set local role ingestion_worker;
 derived:=ingestion.finish_validation_replay(replay::uuid,(claimed->>'lease_token')::uuid,derived_envelope);
 reset role;
 if (select completion from ingestion.ingestion_runs where id=parent)<>'partial'
  or (select completion from ingestion.ingestion_runs where id=derived)<>'complete'
  or (select envelope->'publication_eligible' from ingestion.ingestion_runs where id=derived) is distinct from 'false'::jsonb
  or not exists(select 1 from ingestion.reprocessing_runs where run_id=derived and parent_run_id=parent) then
  raise exception 'Derived lineage or immutable parent gate failed'; end if;
 if (select count(*) from community_orgs.organisations)<>before_orgs then raise exception 'Validation replay published data'; end if;

 begin update ingestion.validation_issues set detail='tampered' where id=issue::bigint;
  raise exception 'Expected immutable issue rejection'; exception when object_not_in_prerequisite_state then null; end;

 insert into ingestion.raw_retention_policies(source_id,resource_id,retain_days,hold,reason)
 values('acnc-register','p34a-fixture',1,false,'Synthetic expiry check');
 update ingestion.ingestion_runs set staged_at=now()-interval '2 days' where id=parent;
 perform ingestion.expire_raw_evidence('acnc-register','p34a-fixture',true);
 if (select source_value is not null or redacted_at is null from ingestion.validation_issues where id=issue::bigint)
  or (select proposed_value is not null or note<>'Private resolution evidence redacted.' from ingestion.validation_resolutions where issue_id=issue::bigint)
  then raise exception 'Validation evidence was not covered by retention'; end if;
 raise notice 'P34a access, structure, validation, concurrency, replay, lineage, publication and retention gates passed';
end $$;
rollback;
