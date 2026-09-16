-- Run as postgres after the staging migration, on a disposable database.
-- All fixtures roll back. No portal tables are involved.
begin;
insert into ingestion.sources values ('acnc-register','fixture','{"synthetic":true}',true);
do $$
declare
    e jsonb := '{"contract_version":"1.0","source_id":"acnc-register",
      "resource_id":"fixture","run_id":"one","parser_version":"v1",
      "observed_at":"2026-09-16T00:00:00Z","completion":"complete",
      "publication_eligible":false,"scope":{"postcode":"2730"},
      "quarantine":[],"errors":[],"records":[{
      "source_id":"acnc-register","resource_id":"fixture","run_id":"one",
      "native_id":"1","parser_version":"v1","observed_at":"2026-09-16T00:00:00Z",
      "raw":{"name":"Example"},"assertions":[{"field":"entity_name","value":"Example"}]}]}';
    first_run bigint;
    changed jsonb;
begin
    if has_schema_privilege('anon','ingestion','USAGE') or
       has_schema_privilege('authenticated','ingestion','USAGE') or
       has_function_privilege('anon','ingestion.stage_acnc(jsonb)','EXECUTE') or
       has_function_privilege('authenticated','ingestion.stage_acnc(jsonb)','EXECUTE') or
       has_table_privilege('ingestion_worker','ingestion.sources','INSERT') then
        raise exception 'Unexpected client/worker privileges';
    end if;
    if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
       where n.nspname='ingestion' and c.relkind='r' and not c.relrowsecurity) then
        raise exception 'RLS missing';
    end if;
    set local role ingestion_worker;
    first_run := ingestion.stage_acnc(e);
    if ingestion.stage_acnc(e) <> first_run then raise exception 'Replay not idempotent'; end if;
    begin
        perform ingestion.stage_acnc(jsonb_set(e,'{completion}','"partial"'));
        raise exception 'Expected replay rejection';
    exception when raise_exception then
        if sqlerrm <> 'Run key already used with different content' then raise; end if;
    end;
    changed := jsonb_set(jsonb_set(e,'{run_id}','"two"'),'{records,0,run_id}','"two"');
    perform ingestion.stage_acnc(changed);
    begin
        perform ingestion.stage_acnc(jsonb_set(changed,'{resource_id}','"unknown"'));
        raise exception 'Expected source rejection';
    exception when raise_exception then
        if sqlerrm <> 'Source resource not enabled for staging' then raise; end if;
    end;
    changed := jsonb_set(jsonb_set(changed,'{run_id}','"bad"'),'{records,0,run_id}','"bad"');
    begin
        perform ingestion.stage_acnc(jsonb_set(changed,'{records,0,assertions}','[{"field":"x"}]'));
        raise exception 'Expected assertion rejection';
    exception when raise_exception then
        if sqlerrm <> 'Invalid assertion' then raise; end if;
    end;
    reset role;
    if (select count(*) from ingestion.ingestion_runs where resource_id='fixture') <> 2 or
       (select count(*) from ingestion.source_records where resource_id='fixture') <> 1 or
       (select count(*) from ingestion.source_record_versions v join ingestion.source_records r
         on r.id=v.record_id where r.resource_id='fixture') <> 1 then
        raise exception 'Idempotency/versioning/rollback invariant failed';
    end if;
    raise notice 'Staging privileges, replay, version reuse and atomic rejection passed';
end $$;
rollback;
