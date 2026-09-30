-- P31: private registry discovery candidates and an explicit promotion boundary.
-- Discovery is not publication: this migration never writes community_orgs tables.
create table ingestion.registry_seed_releases (
 id bigint generated always as identity primary key,
 source_id text not null,
 resource_id text not null,
 release_key text not null check(length(trim(release_key)) between 1 and 500),
 parser_version text not null check(length(trim(parser_version)) between 1 and 200),
 observed_at timestamptz not null,
 staged_at timestamptz not null default now(),
 completion text not null check(completion in ('complete','partial','failed')),
 scope jsonb not null check(jsonb_typeof(scope)='object'),
 manifest jsonb not null check(jsonb_typeof(manifest)='object'),
 manifest_sha256 text not null check(manifest_sha256 ~ '^[0-9a-f]{64}$'),
 candidate_sha256 text not null check(candidate_sha256 ~ '^[0-9a-f]{64}$'),
 expected_part_count integer not null check(expected_part_count>0),
 completed_part_count integer not null check(completed_part_count between 0 and expected_part_count),
 candidate_count integer not null check(candidate_count>=0),
 retention_policy jsonb not null check(jsonb_typeof(retention_policy)='object'),
 raw_removed_at timestamptz,
 unique(source_id,resource_id,release_key),
 foreign key(source_id,resource_id) references ingestion.sources,
 check((scope->>'kind') in ('configured-registry-scope','complete-source-release')),
 check((scope->>'complete_snapshot') in ('true','false')),
 check(jsonb_typeof(scope->'selection')='object'),
 check(length(trim(scope->>'snapshot_series'))>0),
 check((retention_policy->>'class') in ('hold','scheduled')),
 check(length(trim(retention_policy->>'basis'))>0),
 check((retention_policy->>'class'='hold' and not (retention_policy ? 'raw_expires_at')) or
       (retention_policy->>'class'='scheduled' and retention_policy ? 'raw_expires_at')),
 check(completion<>'complete' or
       (completed_part_count=expected_part_count and scope->>'complete_snapshot'='true'))
);

create table ingestion.registry_seed_release_parts (
 release_id bigint not null references ingestion.registry_seed_releases on delete restrict,
 part_key text not null check(length(trim(part_key)) between 1 and 500),
 ordinal integer not null check(ordinal>0),
 status text not null check(status in ('complete','failed')),
 expected_sha256 text check(expected_sha256 is null or expected_sha256 ~ '^[0-9a-f]{64}$'),
 observed_sha256 text check(observed_sha256 is null or observed_sha256 ~ '^[0-9a-f]{64}$'),
 record_count bigint check(record_count is null or record_count>=0),
 detail jsonb not null default '{}' check(jsonb_typeof(detail)='object'),
 primary key(release_id,part_key),
 unique(release_id,ordinal),
 check(status<>'complete' or (observed_sha256 is not null and record_count is not null)),
 check(expected_sha256 is null or observed_sha256 is null or expected_sha256=observed_sha256)
);

create table ingestion.registry_seed_candidates (
 id bigint generated always as identity primary key,
 source_id text not null,
 resource_id text not null,
 native_id text not null check(length(trim(native_id)) between 1 and 500),
 created_at timestamptz not null default now(),
 unique(source_id,resource_id,native_id),
 foreign key(source_id,resource_id) references ingestion.sources
);

create table ingestion.registry_seed_candidate_versions (
 id bigint generated always as identity primary key,
 candidate_id bigint not null references ingestion.registry_seed_candidates on delete restrict,
 parser_version text not null,
 content_hash text not null check(content_hash ~ '^[0-9a-f]{64}$'),
 payload jsonb not null check(jsonb_typeof(payload)='object'),
 raw_removed_at timestamptz,
 unique(candidate_id,parser_version,content_hash),
 check(jsonb_typeof(payload->'raw')='object' or payload->'raw_evidence_removed'='true'::jsonb),
 check(jsonb_typeof(payload->'assertions')='array')
);

create table ingestion.registry_seed_release_candidates (
 release_id bigint not null references ingestion.registry_seed_releases on delete restrict,
 version_id bigint not null references ingestion.registry_seed_candidate_versions on delete restrict,
 in_scope boolean not null,
 selection_reasons jsonb not null check(jsonb_typeof(selection_reasons)='array' and jsonb_array_length(selection_reasons)>0),
 primary key(release_id,version_id)
);

create table ingestion.registry_seed_triage (
 version_id bigint primary key references ingestion.registry_seed_candidate_versions on delete restrict,
 revision integer not null default 1 check(revision>0),
 decision text not null check(decision in ('include','exclude','defer','link')),
 target_candidate_id bigint references ingestion.registry_seed_candidates,
 target_record_id bigint references ingestion.source_records,
 note text not null check(length(trim(note)) between 1 and 2000),
 reviewed_by uuid not null references auth.users,
 reviewed_at timestamptz not null default now(),
 check((decision='link') = ((target_candidate_id is not null)::integer+(target_record_id is not null)::integer=1))
);

create table ingestion.registry_seed_triage_events (
 id bigint generated always as identity primary key,
 version_id bigint not null references ingestion.registry_seed_candidate_versions,
 revision integer not null,
 decision text not null,
 target_candidate_id bigint,
 target_record_id bigint,
 note text not null,
 reviewed_by uuid not null,
 reviewed_at timestamptz not null,
 unique(version_id,revision)
);

create table ingestion.registry_seed_promotions (
 release_id bigint not null references ingestion.registry_seed_releases,
 version_id bigint not null references ingestion.registry_seed_candidate_versions,
 run_id bigint not null references ingestion.ingestion_runs,
 staged_version_id bigint not null references ingestion.source_record_versions,
 promoted_by uuid not null references auth.users,
 promoted_at timestamptz not null default now(),
 reason text not null check(length(trim(reason)) between 1 and 2000),
 primary key(release_id,version_id),
 unique(run_id,staged_version_id)
);

create table ingestion.registry_seed_retention_events (
 id bigint generated always as identity primary key,
 release_id bigint not null references ingestion.registry_seed_releases,
 policy jsonb not null,
 applied boolean not null,
 version_count integer not null check(version_count>=0),
 database_actor text not null default session_user,
 occurred_at timestamptz not null default now()
);

create index registry_seed_release_candidates_version_idx on ingestion.registry_seed_release_candidates(version_id);
create index registry_seed_candidates_native_idx on ingestion.registry_seed_candidates(source_id,resource_id,native_id);
create index registry_seed_triage_decision_idx on ingestion.registry_seed_triage(decision,reviewed_at);

alter table ingestion.registry_seed_releases enable row level security;
alter table ingestion.registry_seed_release_parts enable row level security;
alter table ingestion.registry_seed_candidates enable row level security;
alter table ingestion.registry_seed_candidate_versions enable row level security;
alter table ingestion.registry_seed_release_candidates enable row level security;
alter table ingestion.registry_seed_triage enable row level security;
alter table ingestion.registry_seed_triage_events enable row level security;
alter table ingestion.registry_seed_promotions enable row level security;
alter table ingestion.registry_seed_retention_events enable row level security;

revoke all on ingestion.registry_seed_releases,ingestion.registry_seed_release_parts,
 ingestion.registry_seed_candidates,ingestion.registry_seed_candidate_versions,
 ingestion.registry_seed_release_candidates,ingestion.registry_seed_triage,
 ingestion.registry_seed_triage_events,ingestion.registry_seed_promotions,
 ingestion.registry_seed_retention_events from public,anon,authenticated,service_role,ingestion_worker;
revoke all on all sequences in schema ingestion from public,anon,authenticated,service_role,ingestion_worker;

create function ingestion.stage_registry_seed(p_manifest jsonb,p_candidates jsonb)
returns bigint language plpgsql security definer set search_path='' as $$
declare
 v_release_id bigint; existing ingestion.registry_seed_releases; manifest_hash text; candidate_hash text;
 part jsonb; candidate jsonb; selection jsonb; v_candidate_id bigint; v_version_id bigint;
 expected_parts integer; completed_parts integer; candidate_total integer;
 v_payload jsonb; v_content_hash text; retention jsonb; scope jsonb;
begin
 lock table ingestion.registry_seed_releases in row exclusive mode;
 if jsonb_typeof(p_manifest) is distinct from 'object'
  or p_manifest->>'contract_version' is distinct from 'registry-seed-v1'
  or coalesce(length(trim(p_manifest->>'release_id')),0)=0
  or coalesce(length(trim(p_manifest->>'parser_version')),0)=0
  or coalesce(p_manifest->>'completion','') not in ('complete','partial','failed')
  or jsonb_typeof(p_manifest->'scope') is distinct from 'object'
  or jsonb_typeof(p_manifest->'parts') is distinct from 'array'
  or jsonb_typeof(p_manifest->'errors') is distinct from 'array'
  or jsonb_typeof(p_manifest->'retention') is distinct from 'object'
  or jsonb_typeof(p_candidates) is distinct from 'array' then
  raise exception 'Invalid registry seed manifest' using errcode='22023';
 end if;
 if not exists(select 1 from ingestion.sources where source_id=p_manifest->>'source_id'
   and resource_id=p_manifest->>'resource_id' and enabled) then
  raise exception 'Source resource not enabled for registry seeding' using errcode='22023';
 end if;
 scope:=p_manifest->'scope'; retention:=p_manifest->'retention';
 if scope->>'kind' not in ('configured-registry-scope','complete-source-release')
  or scope->>'complete_snapshot' not in ('true','false')
  or jsonb_typeof(scope->'selection') is distinct from 'object'
  or coalesce(length(trim(scope->>'snapshot_series')),0)=0
 or (retention->>'class') not in ('hold','scheduled')
  or coalesce(length(trim(retention->>'basis')),0)=0
  or (retention->>'class'='hold' and (retention ? 'raw_expires_at'))
  or (retention->>'class'='scheduled' and
      (not (retention ? 'raw_expires_at') or (retention->>'raw_expires_at')::timestamptz<=now())) then
  raise exception 'Invalid registry seed scope or retention policy' using errcode='22023';
 end if;
 expected_parts:=jsonb_array_length(p_manifest->'parts');
 candidate_total:=jsonb_array_length(p_candidates);
 select count(*) into completed_parts from jsonb_array_elements(p_manifest->'parts') p
  where p->>'status'='complete';
 if expected_parts=0
  or exists(select 1 from jsonb_array_elements(p_manifest->'parts') p
   where coalesce(length(trim(p->>'part_id')),0)=0
    or coalesce((p->>'ordinal')::integer,0)<=0
    or (p->>'status') not in ('complete','failed')
    or (p->>'status'='complete' and
       (coalesce(p->>'sha256','') !~ '^[0-9a-f]{64}$' or not (p ? 'record_count')))
    or (p ? 'expected_sha256' and coalesce(p->>'expected_sha256','') !~ '^[0-9a-f]{64}$')
    or (p ? 'expected_sha256' and p ? 'sha256'
        and p->>'expected_sha256' is distinct from p->>'sha256'))
  or exists(select 1 from jsonb_array_elements(p_manifest->'parts') p group by p->>'part_id' having count(*)>1)
  or exists(select 1 from jsonb_array_elements(p_manifest->'parts') p group by p->>'ordinal' having count(*)>1)
  or (p_manifest->>'completion'='complete' and
     (completed_parts<>expected_parts or scope->>'complete_snapshot'<>'true'
      or jsonb_array_length(p_manifest->'errors')>0))
  or (p_manifest->>'completion'<>'complete' and completed_parts=expected_parts
      and jsonb_array_length(p_manifest->'errors')=0) then
  raise exception 'Registry seed completeness declaration does not match part inventory' using errcode='22023';
 end if;
 manifest_hash:=encode(sha256(convert_to(p_manifest::text,'UTF8')),'hex');
 candidate_hash:=encode(sha256(convert_to(p_candidates::text,'UTF8')),'hex');
 select * into existing from ingestion.registry_seed_releases where source_id=p_manifest->>'source_id'
  and resource_id=p_manifest->>'resource_id' and release_key=p_manifest->>'release_id';
 if found then
  if existing.manifest_sha256 is distinct from manifest_hash
   or existing.candidate_sha256 is distinct from candidate_hash then
   raise exception 'Release key already used with different content' using errcode='23505';
  end if;
  return existing.id;
 end if;
 insert into ingestion.registry_seed_releases(source_id,resource_id,release_key,parser_version,
  observed_at,completion,scope,manifest,manifest_sha256,candidate_sha256,expected_part_count,completed_part_count,
  candidate_count,retention_policy)
 values(p_manifest->>'source_id',p_manifest->>'resource_id',p_manifest->>'release_id',
  p_manifest->>'parser_version',(p_manifest->>'observed_at')::timestamptz,p_manifest->>'completion',
  scope,p_manifest,manifest_hash,candidate_hash,expected_parts,completed_parts,candidate_total,retention)
 returning id into v_release_id;
 for part in select value from jsonb_array_elements(p_manifest->'parts') loop
  insert into ingestion.registry_seed_release_parts(release_id,part_key,ordinal,status,expected_sha256,
   observed_sha256,record_count,detail)
  values(v_release_id,part->>'part_id',(part->>'ordinal')::integer,part->>'status',part->>'expected_sha256',
   part->>'sha256',case when part ? 'record_count' then (part->>'record_count')::bigint end,
   coalesce(part->'detail','{}'::jsonb));
 end loop;
 if exists(select 1 from jsonb_array_elements(p_candidates) c
  group by c->>'native_id' having count(*)>1) then
  raise exception 'Duplicate registry candidate native IDs' using errcode='22023';
 end if;
 for candidate in select value from jsonb_array_elements(p_candidates) loop
  selection:=candidate->'selection';
  if candidate->>'source_id' is distinct from p_manifest->>'source_id'
   or candidate->>'resource_id' is distinct from p_manifest->>'resource_id'
   or candidate->>'release_id' is distinct from p_manifest->>'release_id'
   or candidate->>'parser_version' is distinct from p_manifest->>'parser_version'
   or candidate->>'observed_at' is distinct from p_manifest->>'observed_at'
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
   raise exception 'Invalid registry seed candidate' using errcode='22023';
  end if;
  insert into ingestion.registry_seed_candidates(source_id,resource_id,native_id)
  values(candidate->>'source_id',candidate->>'resource_id',candidate->>'native_id')
  on conflict(source_id,resource_id,native_id) do update set native_id=excluded.native_id
  returning id into v_candidate_id;
  v_payload:=candidate-'release_id'-'observed_at';
  v_content_hash:=encode(sha256(convert_to(v_payload::text,'UTF8')),'hex');
  insert into ingestion.registry_seed_candidate_versions(candidate_id,parser_version,content_hash,payload)
  values(v_candidate_id,candidate->>'parser_version',v_content_hash,v_payload)
  on conflict(candidate_id,parser_version,content_hash) do update set content_hash=excluded.content_hash
  returning id into v_version_id;
  insert into ingestion.registry_seed_release_candidates(release_id,version_id,in_scope,selection_reasons)
  values(v_release_id,v_version_id,(selection->>'in_scope')::boolean,selection->'reasons');
 end loop;
 return v_release_id;
end $$;

create function community_orgs.save_registry_seed_triage(
 p_version text,p_revision integer,p_decision text,p_target_candidate text default null,
 p_target_record text default null,p_note text default ''
) returns void language plpgsql security definer set search_path='' as $$
declare current_triage ingestion.registry_seed_triage; v_candidate_id bigint;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then
  raise exception 'Ingestion operator access required' using errcode='42501'; end if;
 if p_revision is null or p_revision<0 or p_decision not in ('include','exclude','defer','link')
  or coalesce(length(trim(p_note)),0) not between 1 and 2000
  or ((p_decision='link') is distinct from
      (((p_target_candidate is not null)::integer+(p_target_record is not null)::integer)=1)) then
  raise exception 'Invalid registry seed triage decision' using errcode='22023'; end if;
 select candidate_id into v_candidate_id from ingestion.registry_seed_candidate_versions where id=p_version::bigint;
 if not found then raise exception 'Registry candidate version not found' using errcode='P0002'; end if;
 if p_target_candidate is not null and p_target_candidate::bigint=v_candidate_id then
  raise exception 'Candidate cannot link to itself' using errcode='22023'; end if;
 if p_revision=0 then
  insert into ingestion.registry_seed_triage(version_id,decision,target_candidate_id,target_record_id,note,reviewed_by)
  values(p_version::bigint,p_decision,p_target_candidate::bigint,p_target_record::bigint,trim(p_note),auth.uid())
  on conflict do nothing returning * into current_triage;
 else
  update ingestion.registry_seed_triage set revision=revision+1,decision=p_decision,
   target_candidate_id=p_target_candidate::bigint,target_record_id=p_target_record::bigint,
   note=trim(p_note),reviewed_by=auth.uid(),reviewed_at=now()
  where version_id=p_version::bigint and revision=p_revision returning * into current_triage;
 end if;
 if current_triage.version_id is null then
  raise exception 'Registry seed triage changed; reload before saving' using errcode='40001'; end if;
 insert into ingestion.registry_seed_triage_events(version_id,revision,decision,target_candidate_id,
  target_record_id,note,reviewed_by,reviewed_at)
 values(current_triage.version_id,current_triage.revision,current_triage.decision,
  current_triage.target_candidate_id,current_triage.target_record_id,current_triage.note,
  current_triage.reviewed_by,current_triage.reviewed_at);
end $$;

create function community_orgs.promote_registry_seed_candidates(
 p_release text,p_versions text[],p_reason text
) returns text language plpgsql security definer set search_path='' as $$
declare
 release ingestion.registry_seed_releases; version_ids bigint[]; v_run_key text; v_run_id bigint;
 envelope jsonb; record jsonb; candidate_version record; v_source_record bigint; v_staged_version bigint;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then
  raise exception 'Ingestion operator access required' using errcode='42501'; end if;
 if coalesce(array_length(p_versions,1),0) not between 1 and 500
  or coalesce(length(trim(p_reason)),0) not between 1 and 2000 then
  raise exception 'A bounded candidate set and reason are required' using errcode='22023'; end if;
 select * into release from ingestion.registry_seed_releases where id=p_release::bigint for share;
 if not found then raise exception 'Registry seed release not found' using errcode='P0002'; end if;
 if release.completion<>'complete' or release.completed_part_count<>release.expected_part_count
  or release.scope->>'complete_snapshot'<>'true' or release.raw_removed_at is not null then
  raise exception 'Only a complete retained registry seed release can be promoted' using errcode='22023'; end if;
 select array_agg(distinct x::bigint order by x::bigint) into version_ids from unnest(p_versions) x;
 if cardinality(version_ids)<>cardinality(p_versions)
  or exists(select 1 from unnest(version_ids) x where not exists(
    select 1 from ingestion.registry_seed_release_candidates rc
    join ingestion.registry_seed_triage t on t.version_id=rc.version_id
    where rc.release_id=release.id and rc.version_id=x and rc.in_scope
     and t.decision in ('include','link'))) then
  raise exception 'Every promoted version must be in scope and triaged include/link' using errcode='22023'; end if;
 if not exists(select 1 from ingestion.sources where source_id=release.source_id
   and resource_id=release.resource_id and enabled) then
  raise exception 'Source resource not enabled for promotion' using errcode='22023'; end if;
 v_run_key:='registry-seed:'||release.id::text||':'||encode(sha256(convert_to(array_to_string(version_ids,','),'UTF8')),'hex');
 select coalesce(jsonb_agg(cv.payload || jsonb_build_object('run_id',v_run_key,
  'observed_at',release.observed_at) order by cv.id),'[]'::jsonb) into record
 from ingestion.registry_seed_candidate_versions cv where cv.id=any(version_ids);
 envelope:=jsonb_build_object('contract_version','1.0','source_id',release.source_id,
  'resource_id',release.resource_id,'run_id',v_run_key,'parser_version',release.parser_version,
  'observed_at',release.observed_at,'completion','complete','publication_eligible',false,
  'scope',release.scope||jsonb_build_object('registry_seed_release_id',release.id,'complete_snapshot',false),
  'quarantine','[]'::jsonb,'errors','[]'::jsonb,'records',record);
 insert into ingestion.ingestion_runs(source_id,resource_id,run_key,completion,observed_at,envelope)
 values(release.source_id,release.resource_id,v_run_key,'complete',release.observed_at,envelope)
 on conflict(source_id,resource_id,run_key) do nothing returning id into v_run_id;
 if v_run_id is null then
  select id into v_run_id from ingestion.ingestion_runs where source_id=release.source_id
   and resource_id=release.resource_id and ingestion_runs.run_key=v_run_key;
 end if;
 for candidate_version in select cv.*,c.native_id from ingestion.registry_seed_candidate_versions cv
  join ingestion.registry_seed_candidates c on c.id=cv.candidate_id where cv.id=any(version_ids) order by cv.id loop
  insert into ingestion.source_records(source_id,resource_id,native_id)
  values(release.source_id,release.resource_id,candidate_version.native_id)
  on conflict(source_id,resource_id,native_id) do update set native_id=excluded.native_id returning id into v_source_record;
  insert into ingestion.source_record_versions(record_id,parser_version,content_hash,payload)
  values(v_source_record,candidate_version.parser_version,candidate_version.content_hash,candidate_version.payload)
  on conflict(record_id,parser_version,content_hash) do update set content_hash=excluded.content_hash returning id into v_staged_version;
  insert into ingestion.run_records(run_id,version_id) values(v_run_id,v_staged_version) on conflict do nothing;
  insert into ingestion.field_assertions(version_id,field,value)
  select v_staged_version,a->>'field',a->'value' from jsonb_array_elements(candidate_version.payload->'assertions') a
  on conflict(version_id,field) do nothing;
  insert into ingestion.registry_seed_promotions(release_id,version_id,run_id,staged_version_id,promoted_by,reason)
  values(release.id,candidate_version.id,v_run_id,v_staged_version,auth.uid(),trim(p_reason)) on conflict do nothing;
 end loop;
 return v_run_id::text;
end $$;

create function community_orgs.expire_registry_seed_raw(p_release text,p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare release ingestion.registry_seed_releases; version_ids bigint[]; expires_at timestamptz;
begin
 if community_orgs.is_platform_admin() is distinct from true then
  raise exception 'Administrator required' using errcode='42501'; end if;
 select * into release from ingestion.registry_seed_releases where id=p_release::bigint for update;
 if not found then raise exception 'Registry seed release not found' using errcode='P0002'; end if;
 if release.retention_policy->>'class'<>'scheduled' then
  return jsonb_build_object('held',true,'applied',false,'versions',0); end if;
 expires_at:=(release.retention_policy->>'raw_expires_at')::timestamptz;
 if expires_at>now() then
  return jsonb_build_object('held',true,'applied',false,'expires_at',expires_at,'versions',0); end if;
 select coalesce(array_agg(v.id),'{}') into version_ids
 from ingestion.registry_seed_release_candidates rc
 join ingestion.registry_seed_candidate_versions v on v.id=rc.version_id
 where rc.release_id=release.id and v.raw_removed_at is null
  and not exists(select 1 from ingestion.registry_seed_release_candidates other
   join ingestion.registry_seed_releases other_release on other_release.id=other.release_id
   where other.version_id=v.id and other.release_id<>release.id
    and (other_release.retention_policy->>'class'='hold'
     or (other_release.retention_policy->>'raw_expires_at')::timestamptz>now()));
 if coalesce(p_apply,false) then
  update ingestion.registry_seed_candidate_versions set
   payload=(payload-'raw')||jsonb_build_object('raw_evidence_removed',true),raw_removed_at=now()
   where id=any(version_ids);
  update ingestion.registry_seed_releases set raw_removed_at=now() where id=release.id;
 end if;
 insert into ingestion.registry_seed_retention_events(release_id,policy,applied,version_count)
 values(release.id,release.retention_policy,coalesce(p_apply,false),cardinality(version_ids));
 return jsonb_build_object('held',false,'applied',coalesce(p_apply,false),'expires_at',expires_at,
  'versions',cardinality(version_ids));
end $$;

revoke all on function ingestion.stage_registry_seed(jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function ingestion.stage_registry_seed(jsonb,jsonb) to ingestion_worker;
revoke all on function community_orgs.save_registry_seed_triage(text,integer,text,text,text,text),
 community_orgs.promote_registry_seed_candidates(text,text[],text),
 community_orgs.expire_registry_seed_raw(text,boolean) from public,anon,service_role,ingestion_worker;
grant execute on function community_orgs.save_registry_seed_triage(text,integer,text,text,text,text),
 community_orgs.promote_registry_seed_candidates(text,text[],text),
 community_orgs.expire_registry_seed_raw(text,boolean) to authenticated;

comment on table ingestion.registry_seed_releases is
 'Private discovery releases. Complete means every declared part for the configured scope succeeded; it does not authorise publication.';
comment on table ingestion.registry_seed_candidates is
 'Private registry identities. Candidate presence is discovery evidence, not evidence of community relevance or public visibility.';
comment on function community_orgs.promote_registry_seed_candidates(text,text[],text) is
 'Moves a bounded, reasoned candidate set into existing private reviewed staging. It never creates or publishes organisations.';
