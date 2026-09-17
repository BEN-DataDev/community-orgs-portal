-- Hosted smoke check through the actual restricted worker LOGIN.
-- psql -v resource=<enabled ACNC resource UUID> -f this-file.sql
-- Synthetic records and staging writes are rolled back; identity sequences advance.
begin;
set local lock_timeout='5s';
set local statement_timeout='20s';
select set_config('test.resource', :'resource', true);
do $$ begin
 if session_user <> 'community_orgs_acquisition' then
  raise exception 'Use the restricted worker LOGIN';
 end if;
end $$;
set local role ingestion_worker;
do $$
declare e jsonb; resource text:=current_setting('test.resource'); first_run bigint;
begin
 e:=jsonb_build_object('contract_version','1.0','source_id','acnc-register',
  'resource_id',resource,'run_id','p09-hosted-worker-'||gen_random_uuid()::text,
  'parser_version','p09-synthetic','observed_at',now()::text,'completion','complete',
  'publication_eligible',false,'synthetic',true,'scope',jsonb_build_object('kind','synthetic-rollback-test'),
  'quarantine','[]'::jsonb,'errors','[]'::jsonb);
 e:=e||jsonb_build_object('records',jsonb_build_array(jsonb_build_object(
  'source_id','acnc-register','resource_id',resource,'run_id',e->>'run_id',
  'native_id','p09-hosted-worker-synthetic','parser_version','p09-synthetic',
  'observed_at',e->>'observed_at','raw',jsonb_build_object('name','P09 rollback-only fixture'),
  'assertions',jsonb_build_array(jsonb_build_object('field','entity_name','value','P09 rollback-only fixture')))));
 first_run:=ingestion.stage_acnc(e);
 if first_run is null or ingestion.stage_acnc(e)<>first_run then
  raise exception 'Worker staging replay failed'; end if;
 begin
  perform ingestion.stage_acnc_before_retention(e);
  raise exception 'Worker bypass unexpectedly allowed';
 exception when insufficient_privilege then null; end;
 begin
  perform ingestion.expire_raw_evidence('acnc-register',resource,true);
  raise exception 'Worker cleanup unexpectedly allowed';
 exception when insufficient_privilege then null; end;
 begin
  perform count(*) from ingestion.raw_retention_policies;
  raise exception 'Worker direct private read unexpectedly allowed';
 exception when insufficient_privilege then null; end;
end $$;
rollback;
select 'P09 restricted worker LOGIN: staging, replay and denial checks passed' as result;
