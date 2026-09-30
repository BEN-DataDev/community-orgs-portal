-- Stage large registry-seed releases in bounded resumable batches. Upload rows
-- remain private and cannot be promoted; final release rows appear atomically only
-- after the complete ordered candidate set has been validated.
create table ingestion.registry_seed_uploads (
 id bigint generated always as identity primary key,
 source_id text not null,
 resource_id text not null,
 release_key text not null,
 manifest jsonb not null check(jsonb_typeof(manifest)='object'),
 manifest_sha256 text not null check(manifest_sha256 ~ '^[0-9a-f]{64}$'),
 expected_candidate_count integer not null check(expected_candidate_count>=0),
 received_candidate_count integer not null default 0 check(received_candidate_count>=0),
 status text not null default 'loading' check(status in ('loading','finalized')),
 candidate_sha256 text check(candidate_sha256 is null or candidate_sha256 ~ '^[0-9a-f]{64}$'),
 release_id bigint references ingestion.registry_seed_releases,
 created_at timestamptz not null default now(),
 finalized_at timestamptz,
 unique(source_id,resource_id,release_key),
 foreign key(source_id,resource_id) references ingestion.sources,
 check((status='loading' and release_id is null and candidate_sha256 is null and finalized_at is null)
    or (status='finalized' and release_id is not null and candidate_sha256 is not null and finalized_at is not null))
);

create table ingestion.registry_seed_upload_candidates (
 upload_id bigint not null references ingestion.registry_seed_uploads on delete cascade,
 ordinal integer not null check(ordinal>=0),
 native_id text not null check(length(trim(native_id)) between 1 and 500),
 candidate jsonb not null check(jsonb_typeof(candidate)='object'),
 primary key(upload_id,ordinal),
 unique(upload_id,native_id)
);

alter table ingestion.registry_seed_uploads enable row level security;
alter table ingestion.registry_seed_upload_candidates enable row level security;
revoke all on ingestion.registry_seed_uploads,ingestion.registry_seed_upload_candidates
 from public,anon,authenticated,service_role,ingestion_worker;
revoke all on all sequences in schema ingestion
 from public,anon,authenticated,service_role,ingestion_worker;

create function ingestion.begin_registry_seed_upload(p_manifest jsonb,p_expected_candidates integer)
returns table(upload_id bigint,finalized boolean,release_id bigint)
language plpgsql security definer set search_path='' as $$
declare
 existing ingestion.registry_seed_uploads; manifest_hash text; scope jsonb; retention jsonb;
 expected_parts integer; completed_parts integer;
begin
 lock table ingestion.registry_seed_uploads in row exclusive mode;
 if jsonb_typeof(p_manifest) is distinct from 'object'
  or p_manifest->>'contract_version' is distinct from 'registry-seed-v1'
  or coalesce(length(trim(p_manifest->>'release_id')),0)=0
  or coalesce(length(trim(p_manifest->>'parser_version')),0)=0
  or p_manifest->>'completion' is distinct from 'complete'
  or jsonb_typeof(p_manifest->'scope') is distinct from 'object'
  or jsonb_typeof(p_manifest->'parts') is distinct from 'array'
  or jsonb_typeof(p_manifest->'errors') is distinct from 'array'
  or jsonb_typeof(p_manifest->'retention') is distinct from 'object'
  or p_expected_candidates is null or p_expected_candidates<0 then
  raise exception 'Invalid chunked registry seed manifest' using errcode='22023';
 end if;
 if not exists(select 1 from ingestion.sources where source_id=p_manifest->>'source_id'
   and resource_id=p_manifest->>'resource_id' and enabled) then
  raise exception 'Source resource not enabled for registry seeding' using errcode='22023';
 end if;
 scope:=p_manifest->'scope'; retention:=p_manifest->'retention';
 if scope->>'kind' not in ('configured-registry-scope','complete-source-release')
  or scope->>'complete_snapshot' is distinct from 'true'
  or jsonb_typeof(scope->'selection') is distinct from 'object'
  or coalesce(length(trim(scope->>'snapshot_series')),0)=0
  or retention->>'class' not in ('hold','scheduled')
  or coalesce(length(trim(retention->>'basis')),0)=0
  or (retention->>'class'='hold' and (retention ? 'raw_expires_at'))
  or (retention->>'class'='scheduled' and
      (not (retention ? 'raw_expires_at') or (retention->>'raw_expires_at')::timestamptz<=now())) then
  raise exception 'Invalid chunked registry seed scope or retention policy' using errcode='22023';
 end if;
 expected_parts:=jsonb_array_length(p_manifest->'parts');
 select count(*) into completed_parts from jsonb_array_elements(p_manifest->'parts') p
  where p->>'status'='complete';
 if expected_parts=0 or completed_parts<>expected_parts
  or jsonb_array_length(p_manifest->'errors')<>0
  or exists(select 1 from jsonb_array_elements(p_manifest->'parts') p
   where coalesce(length(trim(p->>'part_id')),0)=0
    or coalesce((p->>'ordinal')::integer,0)<=0
    or p->>'status' is distinct from 'complete'
    or coalesce(p->>'sha256','') !~ '^[0-9a-f]{64}$'
    or not (p ? 'record_count')
    or (p ? 'expected_sha256' and coalesce(p->>'expected_sha256','') !~ '^[0-9a-f]{64}$')
    or (p ? 'expected_sha256' and p->>'expected_sha256' is distinct from p->>'sha256'))
  or exists(select 1 from jsonb_array_elements(p_manifest->'parts') p
   group by p->>'part_id' having count(*)>1)
  or exists(select 1 from jsonb_array_elements(p_manifest->'parts') p
   group by p->>'ordinal' having count(*)>1) then
  raise exception 'Chunked registry seed completeness does not match part inventory' using errcode='22023';
 end if;
 manifest_hash:=encode(sha256(convert_to(p_manifest::text,'UTF8')),'hex');
 select * into existing from ingestion.registry_seed_uploads
  where source_id=p_manifest->>'source_id' and resource_id=p_manifest->>'resource_id'
   and release_key=p_manifest->>'release_id';
 if found then
  if existing.manifest_sha256 is distinct from manifest_hash
   or existing.expected_candidate_count is distinct from p_expected_candidates then
   raise exception 'Registry seed upload key already used with different content' using errcode='23505';
  end if;
  return query select existing.id,existing.status='finalized',existing.release_id;
  return;
 end if;
 insert into ingestion.registry_seed_uploads(source_id,resource_id,release_key,manifest,
  manifest_sha256,expected_candidate_count)
 values(p_manifest->>'source_id',p_manifest->>'resource_id',p_manifest->>'release_id',
  p_manifest,manifest_hash,p_expected_candidates)
 returning id into upload_id;
 finalized:=false; release_id:=null;
 return next;
end $$;

create function ingestion.append_registry_seed_upload(
 p_upload bigint,p_offset integer,p_candidates jsonb
) returns integer language plpgsql security definer set search_path='' as $$
declare
 upload ingestion.registry_seed_uploads; candidate jsonb; selection jsonb;
 candidate_ordinal integer; existing jsonb; batch_count integer;
begin
 select * into upload from ingestion.registry_seed_uploads where id=p_upload for update;
 if not found then raise exception 'Registry seed upload not found' using errcode='P0002'; end if;
 if upload.status<>'loading' then
  raise exception 'Registry seed upload already finalized' using errcode='22023'; end if;
 if not exists(select 1 from ingestion.sources where source_id=upload.source_id
   and resource_id=upload.resource_id and enabled) then
  raise exception 'Source resource not enabled for registry seeding' using errcode='22023';
 end if;
 if p_offset is null or p_offset<0 or jsonb_typeof(p_candidates) is distinct from 'array' then
  raise exception 'Invalid registry seed upload batch' using errcode='22023'; end if;
 batch_count:=jsonb_array_length(p_candidates);
 if batch_count not between 1 and 500
  or p_offset+batch_count>upload.expected_candidate_count then
  raise exception 'Registry seed upload batch exceeds bounds' using errcode='22023'; end if;
 for candidate,candidate_ordinal in
  select value,p_offset+ordinality-1 from jsonb_array_elements(p_candidates) with ordinality
 loop
  selection:=candidate->'selection';
  if candidate->>'source_id' is distinct from upload.manifest->>'source_id'
   or candidate->>'resource_id' is distinct from upload.manifest->>'resource_id'
   or candidate->>'release_id' is distinct from upload.manifest->>'release_id'
   or candidate->>'parser_version' is distinct from upload.manifest->>'parser_version'
   or candidate->>'observed_at' is distinct from upload.manifest->>'observed_at'
   or coalesce(length(trim(candidate->>'native_id')),0)=0
   or jsonb_typeof(candidate->'raw') is distinct from 'object'
   or jsonb_typeof(candidate->'assertions') is distinct from 'array'
   or jsonb_typeof(selection) is distinct from 'object'
   or selection->'in_scope' not in ('true'::jsonb,'false'::jsonb)
   or jsonb_typeof(selection->'reasons') is distinct from 'array'
   or jsonb_array_length(selection->'reasons')=0
   or exists(select 1 from jsonb_array_elements(candidate->'assertions') a
      group by a->>'field' having count(*)>1)
   or exists(select 1 from jsonb_array_elements(candidate->'assertions') a
      where coalesce(length(trim(a->>'field')),0)=0 or not (a ? 'value')) then
   raise exception 'Invalid registry seed upload candidate' using errcode='22023';
  end if;
  select c.candidate into existing from ingestion.registry_seed_upload_candidates c
   where c.upload_id=p_upload and c.ordinal=candidate_ordinal;
  if found then
   if existing is distinct from candidate then
    raise exception 'Registry seed upload ordinal changed on replay' using errcode='23505'; end if;
  else
   insert into ingestion.registry_seed_upload_candidates(upload_id,ordinal,native_id,candidate)
   values(p_upload,candidate_ordinal,candidate->>'native_id',candidate);
  end if;
 end loop;
 select count(*) into upload.received_candidate_count
  from ingestion.registry_seed_upload_candidates where upload_id=p_upload;
 update ingestion.registry_seed_uploads set received_candidate_count=upload.received_candidate_count
  where id=p_upload;
 return upload.received_candidate_count;
end $$;

create function ingestion.finalize_registry_seed_upload(p_upload bigint)
returns bigint language plpgsql security definer set search_path='' as $$
declare
 upload ingestion.registry_seed_uploads; manifest jsonb; scope jsonb; retention jsonb;
 candidate_hash text; v_release_id bigint; existing ingestion.registry_seed_releases;
 expected_parts integer; completed_parts integer; candidate_total integer; part jsonb;
begin
 lock table ingestion.registry_seed_releases in row exclusive mode;
 select * into upload from ingestion.registry_seed_uploads where id=p_upload for update;
 if not found then raise exception 'Registry seed upload not found' using errcode='P0002'; end if;
 if upload.status='finalized' then return upload.release_id; end if;
 if not exists(select 1 from ingestion.sources where source_id=upload.source_id
   and resource_id=upload.resource_id and enabled) then
  raise exception 'Source resource not enabled for registry seeding' using errcode='22023'; end if;
 select count(*),encode(sha256(convert_to(coalesce(string_agg(
   encode(sha256(convert_to(candidate::text,'UTF8')),'hex'),'' order by ordinal),''),'UTF8')),'hex')
  into candidate_total,candidate_hash from ingestion.registry_seed_upload_candidates
  where upload_id=p_upload;
 if candidate_total<>upload.expected_candidate_count
  or upload.received_candidate_count<>upload.expected_candidate_count
  or (candidate_total>0 and (select min(ordinal) from ingestion.registry_seed_upload_candidates where upload_id=p_upload)<>0)
  or (candidate_total>0 and (select max(ordinal) from ingestion.registry_seed_upload_candidates where upload_id=p_upload)<>candidate_total-1) then
  raise exception 'Registry seed upload is incomplete' using errcode='22023'; end if;
 manifest:=upload.manifest; scope:=manifest->'scope'; retention:=manifest->'retention';
 expected_parts:=jsonb_array_length(manifest->'parts'); completed_parts:=expected_parts;
 select * into existing from ingestion.registry_seed_releases where source_id=upload.source_id
  and resource_id=upload.resource_id and release_key=upload.release_key;
 if found then
  if existing.manifest_sha256 is distinct from upload.manifest_sha256
   or existing.candidate_sha256 is distinct from candidate_hash
   or existing.candidate_count is distinct from candidate_total then
   raise exception 'Release key already used with different chunked content' using errcode='23505'; end if;
  v_release_id:=existing.id;
 else
  insert into ingestion.registry_seed_releases(source_id,resource_id,release_key,parser_version,
   observed_at,completion,scope,manifest,manifest_sha256,candidate_sha256,expected_part_count,
   completed_part_count,candidate_count,retention_policy)
  values(upload.source_id,upload.resource_id,upload.release_key,manifest->>'parser_version',
   (manifest->>'observed_at')::timestamptz,'complete',scope,manifest,upload.manifest_sha256,
   candidate_hash,expected_parts,completed_parts,candidate_total,retention)
  returning id into v_release_id;
  for part in select value from jsonb_array_elements(manifest->'parts') loop
   insert into ingestion.registry_seed_release_parts(release_id,part_key,ordinal,status,
    expected_sha256,observed_sha256,record_count,detail)
   values(v_release_id,part->>'part_id',(part->>'ordinal')::integer,'complete',
    part->>'expected_sha256',part->>'sha256',(part->>'record_count')::bigint,
    coalesce(part->'detail','{}'::jsonb));
  end loop;
  insert into ingestion.registry_seed_candidates(source_id,resource_id,native_id)
  select upload.source_id,upload.resource_id,u.native_id
  from ingestion.registry_seed_upload_candidates u where u.upload_id=p_upload
  on conflict(source_id,resource_id,native_id) do nothing;
  insert into ingestion.registry_seed_candidate_versions(candidate_id,parser_version,content_hash,payload)
  select c.id,manifest->>'parser_version',
   encode(sha256(convert_to((u.candidate-'release_id'-'observed_at')::text,'UTF8')),'hex'),
   u.candidate-'release_id'-'observed_at'
  from ingestion.registry_seed_upload_candidates u
  join ingestion.registry_seed_candidates c on c.source_id=upload.source_id
   and c.resource_id=upload.resource_id and c.native_id=u.native_id
  where u.upload_id=p_upload
  on conflict(candidate_id,parser_version,content_hash) do nothing;
  insert into ingestion.registry_seed_release_candidates(release_id,version_id,in_scope,selection_reasons)
  select v_release_id,v.id,(u.candidate->'selection'->>'in_scope')::boolean,
   u.candidate->'selection'->'reasons'
  from ingestion.registry_seed_upload_candidates u
  join ingestion.registry_seed_candidates c on c.source_id=upload.source_id
   and c.resource_id=upload.resource_id and c.native_id=u.native_id
  join ingestion.registry_seed_candidate_versions v on v.candidate_id=c.id
   and v.parser_version=manifest->>'parser_version'
   and v.content_hash=encode(sha256(convert_to((u.candidate-'release_id'-'observed_at')::text,'UTF8')),'hex')
  where u.upload_id=p_upload;
 end if;
 update ingestion.registry_seed_uploads set status='finalized',candidate_sha256=candidate_hash,
  release_id=v_release_id,finalized_at=now() where id=p_upload;
 return v_release_id;
end $$;

create function ingestion.clear_finalized_registry_seed_upload(p_upload bigint)
returns integer language plpgsql security definer set search_path='' as $$
declare upload ingestion.registry_seed_uploads; removed integer;
begin
 select * into upload from ingestion.registry_seed_uploads where id=p_upload for update;
 if not found then raise exception 'Registry seed upload not found' using errcode='P0002'; end if;
 if upload.status<>'finalized' then
  raise exception 'Only finalized registry seed uploads can be cleared' using errcode='22023'; end if;
 delete from ingestion.registry_seed_upload_candidates where upload_id=p_upload;
 get diagnostics removed=row_count;
 return removed;
end $$;

revoke all on function ingestion.begin_registry_seed_upload(jsonb,integer),
 ingestion.append_registry_seed_upload(bigint,integer,jsonb),
 ingestion.finalize_registry_seed_upload(bigint),
 ingestion.clear_finalized_registry_seed_upload(bigint)
 from public,anon,authenticated,service_role;
grant execute on function ingestion.begin_registry_seed_upload(jsonb,integer),
 ingestion.append_registry_seed_upload(bigint,integer,jsonb),
 ingestion.finalize_registry_seed_upload(bigint),
 ingestion.clear_finalized_registry_seed_upload(bigint)
 to ingestion_worker;

comment on table ingestion.registry_seed_uploads is
 'Private resumable transport state for large registry releases; it cannot be triaged, promoted or published.';
comment on function ingestion.finalize_registry_seed_upload(bigint) is
 'Atomically validates and materializes a complete bounded upload into the private registry seed contract.';
