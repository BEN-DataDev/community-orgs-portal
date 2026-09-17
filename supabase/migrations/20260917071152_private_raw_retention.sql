-- P09: private JSONB raw objects, source-scoped retention and auditable removal.
-- No policy is seeded and no evidence is removed by this migration.
create table ingestion.raw_retention_policies (
 source_id text not null,
 resource_id text not null,
 retain_days integer not null check (retain_days between 1 and 36500),
 hold boolean not null default true,
 reason text not null check (length(trim(reason)) > 0),
 updated_at timestamptz not null default now(),
 primary key(source_id,resource_id),
 foreign key(source_id,resource_id) references ingestion.sources
);
create table ingestion.raw_retention_events (
 id bigint generated always as identity primary key,
 source_id text not null,
 resource_id text not null,
 policy jsonb not null,
 removed_at timestamptz not null default now(),
 database_actor text not null default session_user,
 run_count integer not null,
 version_count integer not null,
 checkpoint_count integer not null
);
alter table ingestion.raw_retention_policies enable row level security;
alter table ingestion.raw_retention_events enable row level security;
revoke all on ingestion.raw_retention_policies, ingestion.raw_retention_events
 from public,anon,authenticated,service_role,ingestion_worker;
revoke all on sequence ingestion.raw_retention_events_id_seq
 from public,anon,authenticated,service_role,ingestion_worker;

alter table ingestion.ingestion_runs add column raw_removed_at timestamptz;
alter table ingestion.ingestion_runs add column envelope_sha256 text;
update ingestion.ingestion_runs set envelope_sha256=encode(sha256(convert_to(envelope::text,'UTF8')),'hex');
alter table ingestion.ingestion_runs alter column envelope_sha256 set not null;
alter table ingestion.source_record_versions add column raw_removed_at timestamptz;
alter table ingestion.acquisition_jobs add column raw_removed_at timestamptz;

create function ingestion.hash_run_envelope() returns trigger
language plpgsql set search_path='' as $$
begin
 new.envelope_sha256 := encode(sha256(convert_to(new.envelope::text,'UTF8')),'hex');
 return new;
end $$;
revoke all on function ingestion.hash_run_envelope() from public,anon,authenticated,service_role,ingestion_worker;
create trigger hash_run_envelope before insert on ingestion.ingestion_runs
 for each row execute function ingestion.hash_run_envelope();

-- Preserve immutable run identity after its original envelope has expired.
alter function ingestion.stage_acnc(jsonb) rename to stage_acnc_before_retention;
revoke all on function ingestion.stage_acnc_before_retention(jsonb)
 from public,anon,authenticated,service_role,ingestion_worker;
create function ingestion.stage_acnc(p_envelope jsonb) returns bigint
language plpgsql security definer set search_path='' as $$
declare r ingestion.ingestion_runs;
begin
 -- Match the acquisition worker's lock order and serialize against maintenance.
 lock table ingestion.ingestion_runs in row exclusive mode;
 if not exists(select 1 from ingestion.sources where source_id=p_envelope->>'source_id'
   and resource_id=p_envelope->>'resource_id' and enabled) then
  raise exception 'Source resource not enabled for staging';
 end if;
 select * into r from ingestion.ingestion_runs where source_id=p_envelope->>'source_id'
  and resource_id=p_envelope->>'resource_id' and run_key=p_envelope->>'run_id';
 if found and r.raw_removed_at is not null then
  if r.envelope_sha256 is distinct from encode(sha256(convert_to(p_envelope::text,'UTF8')),'hex') then
   raise exception 'Run key already used with different content';
  end if;
  return r.id;
 end if;
 return ingestion.stage_acnc_before_retention(p_envelope);
end $$;
revoke all on function ingestion.stage_acnc(jsonb) from public,anon,authenticated,service_role;
grant execute on function ingestion.stage_acnc(jsonb) to ingestion_worker;

-- An expired parent must never look like a genuinely empty retained snapshot.
alter function ingestion.stage_acnc_reprocessing(bigint,jsonb) rename to stage_acnc_reprocessing_before_retention;
revoke all on function ingestion.stage_acnc_reprocessing_before_retention(bigint,jsonb)
 from public,anon,authenticated,service_role,ingestion_worker;
create function ingestion.stage_acnc_reprocessing(p_parent bigint,p_envelope jsonb) returns bigint
language plpgsql security definer set search_path='' as $$
begin
 lock table ingestion.ingestion_runs in row exclusive mode;
 if exists(select 1 from ingestion.ingestion_runs where id=p_parent and raw_removed_at is not null) then
  raise exception 'Raw evidence expired; acquire fresh source evidence';
 end if;
 return ingestion.stage_acnc_reprocessing_before_retention(p_parent,p_envelope);
end $$;
revoke all on function ingestion.stage_acnc_reprocessing(bigint,jsonb) from public,anon,authenticated,service_role;
grant execute on function ingestion.stage_acnc_reprocessing(bigint,jsonb) to ingestion_worker;

-- Administrative maintenance only. Missing policy or hold=true retains evidence.
-- Preview uses the same eligibility and locks as removal; cutoff cannot be advanced.
create function ingestion.expire_raw_evidence(p_source text,p_resource text,p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p ingestion.raw_retention_policies; cutoff timestamptz;
 runs bigint[]; versions bigint[]; jobs uuid[];
begin
 select * into p from ingestion.raw_retention_policies
  where source_id=p_source and resource_id=p_resource for share;
 if not found or p.hold then
  return jsonb_build_object('held',true,'runs',0,'versions',0,'checkpoints',0);
 end if;
 cutoff := now()-make_interval(days=>p.retain_days);
 -- Maintenance is deliberately serialized for the small pilot. Active jobs keep
 -- their checkpoints and block source cleanup until recovery has finished.
 lock table ingestion.acquisition_jobs in share row exclusive mode;
 lock table ingestion.ingestion_runs in share row exclusive mode;
 lock table ingestion.source_record_versions in share row exclusive mode;
 if exists(select 1 from ingestion.acquisition_jobs where source_id=p_source
   and resource_id=p_resource and status in ('queued','running')) then
  return jsonb_build_object('held',true,'runs',0,'versions',0,'checkpoints',0);
 end if;
 select coalesce(array_agg(id),'{}') into runs from ingestion.ingestion_runs
  where source_id=p_source and resource_id=p_resource and staged_at<=cutoff and raw_removed_at is null;
 select coalesce(array_agg(v.id),'{}') into versions from ingestion.source_record_versions v
  join ingestion.source_records r on r.id=v.record_id
  where r.source_id=p_source and r.resource_id=p_resource and v.raw_removed_at is null
   and exists(select 1 from ingestion.run_records rr where rr.version_id=v.id)
   and not exists(select 1 from ingestion.run_records rr join ingestion.ingestion_runs ir on ir.id=rr.run_id
    where rr.version_id=v.id and ir.staged_at>cutoff);
 select coalesce(array_agg(id),'{}') into jobs from ingestion.acquisition_jobs
  where source_id=p_source and resource_id=p_resource and checkpoint is not null
   and status in ('complete','partial','failed','cancelled') and finished_at<=cutoff;
 if p_apply is true then
  update ingestion.ingestion_runs set envelope=(envelope-'records'-'quarantine'-'errors') ||
    jsonb_build_object('records','[]'::jsonb,'quarantine','[]'::jsonb,'errors','[]'::jsonb,
      'raw_evidence_removed',true,'removed_counts',jsonb_build_object(
       'records',jsonb_array_length(envelope->'records'),
       'quarantine',jsonb_array_length(envelope->'quarantine'),
       'errors',jsonb_array_length(envelope->'errors'))),raw_removed_at=now() where id=any(runs);
  update ingestion.source_record_versions set payload=(payload-'raw') || jsonb_build_object('raw_evidence_removed',true),raw_removed_at=now()
   where id=any(versions);
  update ingestion.acquisition_jobs set checkpoint=null,raw_removed_at=now() where id=any(jobs);
  if cardinality(runs)+cardinality(versions)+cardinality(jobs)>0 then
   insert into ingestion.raw_retention_events(source_id,resource_id,policy,run_count,version_count,checkpoint_count)
    values(p_source,p_resource,to_jsonb(p),cardinality(runs),cardinality(versions),cardinality(jobs));
  end if;
 end if;
 return jsonb_build_object('held',false,'applied',coalesce(p_apply,false),'cutoff',cutoff,
  'runs',cardinality(runs),'versions',cardinality(versions),'checkpoints',cardinality(jobs));
end $$;
revoke all on function ingestion.expire_raw_evidence(text,text,boolean)
 from public,anon,authenticated,service_role,ingestion_worker;
comment on table ingestion.raw_retention_policies is
 'Administrator-reviewed raw snapshot retention. Missing policy or hold retains data. Assertions and publication audit are retained separately; this is not personal-data erasure.';
