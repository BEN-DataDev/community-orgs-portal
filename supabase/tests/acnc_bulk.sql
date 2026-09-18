-- Parser-generated P13 fixture, full migrations, disposable database only.
begin;
insert into ingestion.sources(source_id,resource_id,metadata,enabled)
values ('acnc-register','p13-bulk-fixture','{"synthetic":true}',true);
do $$
declare
 e jsonb := current_setting('test.p13_envelope')::jsonb;
 second jsonb;
 run bigint;
 org_count bigint := (select count(*) from community_orgs.organisations);
 publication_count bigint := (select count(*) from ingestion.publications);
begin
 set local role ingestion_worker;
 run := ingestion.stage_acnc(e);
 if ingestion.stage_acnc(e) <> run then raise exception 'Bulk replay duplicated run'; end if;
 second := jsonb_set(jsonb_set(e,'{run_id}','"p13-second"'),'{records,0,run_id}','"p13-second"');
 perform ingestion.stage_acnc(second);
 reset role;
 if (select count(*) from ingestion.source_records where resource_id='p13-bulk-fixture') <> 1
 or (select count(*) from ingestion.source_record_versions v join ingestion.source_records s on s.id=v.record_id
     where s.resource_id='p13-bulk-fixture') <> 1
 or (select count(*) from ingestion.ingestion_runs where resource_id='p13-bulk-fixture') <> 2 then
   raise exception 'Bulk version/run identity mismatch';
 end if;
 if not exists (select 1 from ingestion.source_record_versions v join ingestion.source_records s on s.id=v.record_id
   where s.resource_id='p13-bulk-fixture' and s.native_id='abn:00000000000'
   and v.parser_version='acnc-bulk-v1' and not (v.payload->'raw' ? '_id')
   and jsonb_array_length(v.payload->'assertions')=62) then
   raise exception 'Bulk provenance/mapping lost';
 end if;
 if (select count(*) from community_orgs.organisations) <> org_count
 or (select count(*) from ingestion.publications) <> publication_count
 or exists (select 1 from ingestion.source_links l join ingestion.source_records s on s.id=l.record_id
   where s.resource_id='p13-bulk-fixture') then
   raise exception 'Acquisition published or linked an organisation';
 end if;
end $$;
rollback;
