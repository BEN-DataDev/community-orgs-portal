-- Rollback-only P09 checks, after all portal/ingestion migrations.
begin;
insert into ingestion.sources(source_id,resource_id,metadata,enabled)
 values('acnc-register','p09','{"synthetic":true}',true);
do $$
declare e jsonb := '{"contract_version":"1.0","source_id":"acnc-register",
 "resource_id":"p09","run_id":"old","parser_version":"v1",
 "observed_at":"2026-01-01T00:00:00Z","completion":"partial",
 "publication_eligible":false,"scope":{"postcode":"2730"},
 "quarantine":[{"raw":{"secret":"quarantine"}}],"errors":["private error"],"records":[{
 "source_id":"acnc-register","resource_id":"p09","run_id":"old",
 "native_id":"1","parser_version":"v1","observed_at":"2026-01-01T00:00:00Z",
 "raw":{"name":"Example","extra":"raw-only"},"assertions":[{"field":"entity_name","value":"Example"}]}]}';
 r bigint; v bigint; j uuid; result jsonb; role_name text; table_name text; before_orgs bigint;
begin
 select count(*) into before_orgs from community_orgs.organisations;
 foreach role_name in array array['anon','authenticated','service_role','ingestion_worker'] loop
  if has_function_privilege(role_name,'ingestion.expire_raw_evidence(text,text,boolean)','EXECUTE')
    or has_function_privilege(role_name,'ingestion.stage_acnc_before_retention(jsonb)','EXECUTE')
    or has_function_privilege(role_name,'ingestion.stage_acnc_reprocessing_before_retention(bigint,jsonb)','EXECUTE') then
   raise exception 'Unexpected retention/bypass permission: %',role_name;
  end if;
  foreach table_name in array array['sources','ingestion_runs','source_records','source_record_versions',
    'field_assertions','source_links','change_sets','raw_retention_policies','raw_retention_events'] loop
   if has_table_privilege(role_name,'ingestion.'||table_name,'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'Private table exposed: % %',role_name,table_name;
   end if;
  end loop;
 end loop;
 if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='ingestion' and c.relkind='r' and not c.relrowsecurity) then
  raise exception 'Private table missing RLS';
 end if;
 set local role ingestion_worker;
 r:=ingestion.stage_acnc(e);
 reset role;
 select version_id into v from ingestion.run_records where run_id=r;
 update ingestion.ingestion_runs set staged_at=now()-interval '40 days' where id=r;
 if ingestion.expire_raw_evidence('acnc-register','p09',true)->>'held'<>'true' then
  raise exception 'Missing policy did not hold'; end if;
 insert into ingestion.raw_retention_policies(source_id,resource_id,retain_days,reason)
  values('acnc-register','p09',30,'Synthetic test policy');
 if ingestion.expire_raw_evidence('acnc-register','p09',true)->>'held'<>'true' then
  raise exception 'Default hold ignored'; end if;
 update ingestion.raw_retention_policies set hold=false where resource_id='p09';
 insert into ingestion.acquisition_configs(source_id,resource_id,postcode,licence_title,updated_by)
  values('acnc-register','p09','2730','Synthetic',gen_random_uuid());
 insert into ingestion.acquisition_jobs(source_id,resource_id,config_revision,source_revision,config,origin,
   checkpoint,status,finished_at) values('acnc-register','p09',1,1,'{}','manual',e,'running',null) returning id into j;
 if ingestion.expire_raw_evidence('acnc-register','p09',true)->>'held'<>'true' then
  raise exception 'Active checkpoint not held'; end if;
 update ingestion.acquisition_jobs set status='cancelled',finished_at=now()-interval '40 days' where id=j;
 result:=ingestion.expire_raw_evidence('acnc-register','p09');
 if result->>'runs'<>'1' or result->>'versions'<>'1' or result->>'checkpoints'<>'1'
   or (select raw_removed_at is not null from ingestion.ingestion_runs where id=r) then
  raise exception 'Preview incorrect: %',result; end if;
 -- A fresh observation of the same version extends its raw snapshot lifetime.
 perform ingestion.stage_acnc(jsonb_set(jsonb_set(e,'{run_id}','"fresh"'),'{records,0,run_id}','"fresh"'));
 result:=ingestion.expire_raw_evidence('acnc-register','p09',true);
 if result->>'versions'<>'0' or result->>'runs'<>'1' or result->>'checkpoints'<>'1' then
  raise exception 'Shared version/fresh observation retention failed: %',result; end if;
 if (select checkpoint is not null or raw_removed_at is null from ingestion.acquisition_jobs where id=j)
  or (select envelope::text like '%raw-only%' or envelope::text like '%private error%'
      or envelope::text like '%"secret"%' from ingestion.ingestion_runs where id=r) then
  raise exception 'Expired raw copies survived'; end if;
 update ingestion.ingestion_runs set staged_at=now()-interval '40 days' where resource_id='p09';
 result:=ingestion.expire_raw_evidence('acnc-register','p09',true);
 if result->>'versions'<>'1' or (select payload ? 'raw' from ingestion.source_record_versions where id=v)
  or (select value from ingestion.field_assertions where version_id=v and field='entity_name')<>'"Example"'::jsonb then
  raise exception 'Raw removal damaged assertions or retained raw'; end if;
 set local role ingestion_worker;
 if ingestion.stage_acnc(e)<>r then raise exception 'Expired replay changed identity'; end if;
 begin
  perform ingestion.stage_acnc_reprocessing(r,'{}');
  raise exception 'Expired reprocessing allowed';
 exception when raise_exception then
  if sqlerrm<>'Raw evidence expired; acquire fresh source evidence' then raise; end if;
 end;
 begin
  perform ingestion.stage_acnc(jsonb_set(e,'{errors}','[]'));
  raise exception 'Changed replay allowed';
 exception when raise_exception then
  if sqlerrm<>'Run key already used with different content' then raise; end if;
 end;
 -- A new run reuses the tombstoned version without rehydrating its raw object.
 perform ingestion.stage_acnc(jsonb_set(jsonb_set(e,'{run_id}','"after"'),'{records,0,run_id}','"after"'));
 reset role;
 if (select count(*) from ingestion.source_record_versions sv join ingestion.source_records sr on sr.id=sv.record_id
   where sr.resource_id='p09')<>1 or (select payload ? 'raw' from ingestion.source_record_versions where id=v) then
  raise exception 'Expired version restored or duplicated'; end if;
 if (select count(*) from ingestion.raw_retention_events where resource_id='p09')<>2 then
  raise exception 'Removal audit missing'; end if;
 perform ingestion.expire_raw_evidence('acnc-register','p09',true);
 if (select count(*) from ingestion.raw_retention_events where resource_id='p09')<>2 then
  raise exception 'Empty cleanup duplicated audit'; end if;
 if (select count(*) from community_orgs.organisations)<>before_orgs then
  raise exception 'Staging published an organisation'; end if;
 raise notice 'P09 private storage, retention holds, copies, replay, assertions and audit passed';
end $$;
rollback;
