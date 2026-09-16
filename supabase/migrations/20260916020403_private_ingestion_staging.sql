-- Private acquisition only. No portal tables, publication, ownership or API exposure.
create schema ingestion;
revoke all on schema ingestion from public;
do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'ingestion_worker') then
        create role ingestion_worker nologin nosuperuser nobypassrls;
    end if;
end $$;

create table ingestion.sources (
    source_id text not null,
    resource_id text not null,
    metadata jsonb not null check (jsonb_typeof(metadata) = 'object'),
    enabled boolean not null default false,
    primary key (source_id, resource_id)
);
create table ingestion.ingestion_runs (
    id bigint generated always as identity primary key,
    source_id text not null,
    resource_id text not null,
    run_key text not null,
    completion text not null check (completion in ('complete', 'partial', 'failed')),
    observed_at timestamptz not null,
    staged_at timestamptz not null default now(),
    envelope jsonb not null,
    unique (source_id, resource_id, run_key),
    foreign key (source_id, resource_id) references ingestion.sources
);
create table ingestion.source_records (
    id bigint generated always as identity primary key,
    source_id text not null,
    resource_id text not null,
    native_id text not null,
    unique (source_id, resource_id, native_id),
    foreign key (source_id, resource_id) references ingestion.sources
);
create table ingestion.source_record_versions (
    id bigint generated always as identity primary key,
    record_id bigint not null references ingestion.source_records,
    parser_version text not null,
    content_hash text not null,
    payload jsonb not null,
    unique (record_id, parser_version, content_hash)
);
create table ingestion.run_records (
    run_id bigint not null references ingestion.ingestion_runs,
    version_id bigint not null references ingestion.source_record_versions,
    primary key (run_id, version_id)
);
create table ingestion.field_assertions (
    version_id bigint not null references ingestion.source_record_versions,
    field text not null,
    value jsonb not null,
    primary key (version_id, field)
);

-- Even if schema access is inadvertently broadened later, no browser-role policies exist.
alter table ingestion.sources enable row level security;
alter table ingestion.ingestion_runs enable row level security;
alter table ingestion.source_records enable row level security;
alter table ingestion.source_record_versions enable row level security;
alter table ingestion.run_records enable row level security;
alter table ingestion.field_assertions enable row level security;
revoke all on all tables in schema ingestion from public;
revoke all on all sequences in schema ingestion from public;
-- Supabase roles may inherit default object grants; explicitly remove them here.
do $$ declare r text; begin
    foreach r in array array['anon', 'authenticated', 'service_role'] loop
        if exists (select 1 from pg_roles where rolname = r) then
            execute format('revoke all on schema ingestion from %I', r);
            execute format('revoke all on all tables in schema ingestion from %I', r);
            execute format('revoke all on all sequences in schema ingestion from %I', r);
        end if;
    end loop;
end $$;

create function ingestion.stage_acnc(p_envelope jsonb) returns bigint
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
       or p_envelope->>'source_id' is distinct from 'acnc-register'
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
revoke all on function ingestion.stage_acnc(jsonb) from public;
do $$ declare r text; begin
    foreach r in array array['anon', 'authenticated', 'service_role'] loop
        if exists (select 1 from pg_roles where rolname = r) then
            execute format('revoke all on function ingestion.stage_acnc(jsonb) from %I', r);
        end if;
    end loop;
end $$;
grant usage on schema ingestion to ingestion_worker;
grant execute on function ingestion.stage_acnc(jsonb) to ingestion_worker;

comment on schema ingestion is 'Private staging. Not a PostgREST exposed schema. No publication.';
