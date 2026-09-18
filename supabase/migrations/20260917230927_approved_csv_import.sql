-- P12: qualified CSV staging; no source enablement or public writes.
create function ingestion.stage_csv_records(p_envelope jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
    v_run bigint;
    v_existing jsonb;
    v_record bigint;
    v_version bigint;
    r jsonb;
    a jsonb;
    v_payload jsonb;
begin
    if p_envelope->>'contract_version' is distinct from '1.0'
       or coalesce(p_envelope->>'source_id','') in ('','acnc-register')
       or p_envelope->>'parser_version' is distinct from 'approved-csv-v1'
       or p_envelope->'publication_eligible' is distinct from 'false'::jsonb
       or coalesce(p_envelope->>'completion', '') not in ('complete','partial','failed')
       or coalesce(p_envelope->>'run_id','') = ''
       or coalesce(p_envelope->>'parser_version','') = ''
       or coalesce(p_envelope->>'observed_at','') = ''
       or jsonb_typeof(p_envelope->'scope') is distinct from 'object'
       or jsonb_typeof(p_envelope->'records') is distinct from 'array'
       or jsonb_typeof(p_envelope->'quarantine') is distinct from 'array'
       or jsonb_typeof(p_envelope->'errors') is distinct from 'array' then
        raise exception 'Invalid acquisition envelope';
    end if;
    if p_envelope->>'completion' = 'complete' and
       (jsonb_array_length(p_envelope->'quarantine') > 0 or
        jsonb_array_length(p_envelope->'errors') > 0) then
        raise exception 'Complete run cannot contain errors or quarantine';
    end if;
    if not exists (select 1 from ingestion.sources where
        source_id = p_envelope->>'source_id' and
        resource_id = p_envelope->>'resource_id' and enabled) then
        raise exception 'Source resource not enabled for staging';
    end if;

    insert into ingestion.ingestion_runs
        (source_id, resource_id, run_key, completion, observed_at, envelope)
    values (p_envelope->>'source_id', p_envelope->>'resource_id',
        p_envelope->>'run_id', p_envelope->>'completion',
        (p_envelope->>'observed_at')::timestamptz, p_envelope)
    on conflict (source_id, resource_id, run_key) do nothing returning id into v_run;
    if v_run is null then
        select id, envelope into v_run, v_existing from ingestion.ingestion_runs
        where source_id = p_envelope->>'source_id'
          and resource_id = p_envelope->>'resource_id' and run_key = p_envelope->>'run_id';
        if v_existing is distinct from p_envelope then
            raise exception 'Run key already used with different content';
        end if;
        return v_run;
    end if;

    if exists (select 1 from jsonb_array_elements(p_envelope->'records') x
        group by x->>'native_id' having count(*) > 1) then
        raise exception 'Duplicate native IDs';
    end if;
    for r in select value from jsonb_array_elements(p_envelope->'records') loop
        if coalesce(r->>'native_id','') = ''
           or jsonb_typeof(r->'native_id') is distinct from 'string'
           or r->>'source_id' is distinct from p_envelope->>'source_id'
           or r->>'resource_id' is distinct from p_envelope->>'resource_id'
           or r->>'run_id' is distinct from p_envelope->>'run_id'
           or r->>'parser_version' is distinct from p_envelope->>'parser_version'
           or r->>'observed_at' is distinct from p_envelope->>'observed_at'
           or jsonb_typeof(r->'raw') is distinct from 'object'
           or jsonb_typeof(r->'assertions') is distinct from 'array' then
            raise exception 'Invalid source record';
        end if;
        if exists (select 1 from jsonb_array_elements(r->'assertions') x
            group by x->>'field' having count(*) > 1) then
            raise exception 'Duplicate assertion fields';
        end if;
        insert into ingestion.source_records (source_id, resource_id, native_id)
        values (r->>'source_id', r->>'resource_id', r->>'native_id')
        on conflict (source_id, resource_id, native_id) do update
            set native_id = excluded.native_id returning id into v_record;
        -- Observation/run metadata is separate from semantic record versions.
        v_payload := r - 'run_id' - 'observed_at';
        insert into ingestion.source_record_versions
            (record_id, parser_version, content_hash, payload)
        values (v_record, r->>'parser_version',
            encode(sha256(convert_to(v_payload::text, 'UTF8')), 'hex'), v_payload)
        on conflict (record_id, parser_version, content_hash) do update
            set content_hash = excluded.content_hash returning id into v_version;
        insert into ingestion.run_records values (v_run, v_version);
        for a in select value from jsonb_array_elements(r->'assertions') loop
            if coalesce(a->>'field','') = '' or not a ? 'value' then
                raise exception 'Invalid assertion';
            end if;
            insert into ingestion.field_assertions values (v_version, a->>'field', a->'value')
            on conflict (version_id, field) do nothing;
        end loop;
    end loop;
    return v_run;
end $$;

revoke all on function ingestion.stage_csv_records(jsonb)
 from public,anon,authenticated,service_role,ingestion_worker;

-- Qualification is registered by the source administrator, never by the importer.
-- Retain the P09 lock order and immutable replay check after raw expiry.
create function ingestion.stage_csv(p_envelope jsonb) returns bigint
language plpgsql security definer set search_path='' as $$
declare r ingestion.ingestion_runs; metadata jsonb; q jsonb; record jsonb; a jsonb;
begin
 lock table ingestion.ingestion_runs in row exclusive mode;
 select s.metadata into metadata from ingestion.sources s
 where s.source_id=p_envelope->>'source_id' and s.resource_id=p_envelope->>'resource_id'
 and s.enabled for share;
 if not found then raise exception 'Source resource not enabled for staging'; end if;
 q:=p_envelope->'qualification';
 if jsonb_typeof(q) is distinct from 'object'
 or metadata->'csv_qualification' is distinct from q
 or q->>'manifest_version' is distinct from 'p04-csv-qualification-v1'
 or q->>'source_id' is distinct from p_envelope->>'source_id'
 or q->>'resource_id' is distinct from p_envelope->>'resource_id'
 or q->>'observed_at' is distinct from p_envelope->>'observed_at'
 or q->'scope' is distinct from p_envelope->'scope'
 or q->'publication_eligible' is distinct from 'false'::jsonb
 or p_envelope->'publication_eligible' is distinct from 'false'::jsonb
 or q->'synthetic' is distinct from p_envelope->'synthetic'
 or q->'synthetic' not in ('true'::jsonb,'false'::jsonb)
 or q->'synthetic' is null
 or p_envelope->>'parser_version' is distinct from 'approved-csv-v1'
 or p_envelope->>'source_id'='acnc-register'
 or (q->'synthetic'='false'::jsonb and q->>'access_status' is distinct from 'approved')
 or (q->'synthetic'='true'::jsonb and (q->>'access_status' is distinct from 'development_fixture_only'
     or p_envelope->>'completion'='complete'))
 then raise exception 'CSV qualification does not match approved source metadata'; end if;
 for record in select value from jsonb_array_elements(p_envelope->'records') loop
  if record->>'mapping_version' is distinct from 'portal-csv-pilot-v1' then
   raise exception 'Unsupported CSV mapping'; end if;
  for a in select value from jsonb_array_elements(record->'assertions') loop
   if a->>'field' not in ('entity_name','abn','website') and left(a->>'field',4)<>'csv_' then
    raise exception 'Unsupported CSV assertion'; end if;
  end loop;
 end loop;
 select * into r from ingestion.ingestion_runs where source_id=p_envelope->>'source_id'
 and resource_id=p_envelope->>'resource_id' and run_key=p_envelope->>'run_id';
 if found and r.raw_removed_at is not null then
  if r.envelope_sha256 is distinct from encode(sha256(convert_to(p_envelope::text,'UTF8')),'hex') then
   raise exception 'Run key already used with different content'; end if;
  return r.id;
 end if;
 return ingestion.stage_csv_records(p_envelope);
end $$;
revoke all on function ingestion.stage_csv(jsonb) from public,anon,authenticated,service_role;
grant execute on function ingestion.stage_csv(jsonb) to ingestion_worker;
