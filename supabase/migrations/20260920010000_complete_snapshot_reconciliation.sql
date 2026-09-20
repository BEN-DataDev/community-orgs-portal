-- P27: review-gated reconciliation for genuinely complete snapshots.
-- Filtered acquisitions and incomplete runs remain incapable of closure/removal.
create function ingestion.complete_snapshot_scope_key(p_scope jsonb)
returns jsonb language sql immutable set search_path='' as $$
 select coalesce(p_scope,'{}'::jsonb) - array['release','release_id','released_at','snapshot_at']::text[]
$$;

create table ingestion.complete_snapshot_sources (
 source_id text not null,
 resource_id text not null,
 scope jsonb not null check(jsonb_typeof(scope)='object'),
 identity jsonb not null check(jsonb_typeof(identity)='object'),
 note text not null check(length(trim(note)) between 1 and 2000),
 active boolean not null default true,
 qualified_by uuid not null references auth.users,
 qualified_at timestamptz not null default now(),
 primary key(source_id,resource_id,scope),
 foreign key(source_id,resource_id) references ingestion.sources,
 check(scope->>'complete_snapshot'='true'),
 check(coalesce(scope->>'kind','')='complete-snapshot'),
 check(coalesce(length(trim(scope->>'snapshot_series')),0)>0),
 check(not scope ? 'filters'),
 check(scope=ingestion.complete_snapshot_scope_key(scope)),
 check(identity->>'native_id_stable'='true')
);

create table ingestion.reconciliation_actions (
 id uuid primary key default gen_random_uuid(),
 run_id bigint not null references ingestion.ingestion_runs,
 baseline_run_id bigint not null references ingestion.ingestion_runs,
 record_id bigint not null references ingestion.source_records,
 organisation_id uuid not null references community_orgs.organisations,
 action text not null check(action in ('closure','suppress','remove','no_action')),
 reason text not null check(length(trim(reason)) between 1 and 2000),
 expected jsonb not null check(jsonb_typeof(expected)='object'),
 approved_by uuid not null references auth.users,
 approved_at timestamptz not null default now(),
 applied_at timestamptz,
 result jsonb,
 unique(run_id,baseline_run_id,record_id,action)
);

alter table ingestion.complete_snapshot_sources enable row level security;
alter table ingestion.reconciliation_actions enable row level security;
revoke all on ingestion.complete_snapshot_sources,ingestion.reconciliation_actions from public,anon,authenticated,service_role,ingestion_worker;

create function ingestion.reconciliation_missing_reason(p_run bigint,p_baseline bigint)
returns text language plpgsql stable security definer set search_path='' as $$
declare r ingestion.ingestion_runs; b ingestion.ingestion_runs;
begin
 select * into r from ingestion.ingestion_runs where id=p_run;
 if not found then raise exception 'Run not found' using errcode='P0002'; end if;
 select * into b from ingestion.ingestion_runs where id=p_baseline;
 if not found then raise exception 'Baseline not found' using errcode='P0002'; end if;
 if (b.source_id,b.resource_id) is distinct from (r.source_id,r.resource_id)
  or b.id=r.id or b.observed_at>=r.observed_at
  or ingestion.complete_snapshot_scope_key(b.envelope->'scope')
   is distinct from ingestion.complete_snapshot_scope_key(r.envelope->'scope') then
  return 'Baseline must be an earlier observation of the same source, resource and scope';
 end if;
 if r.completion<>'complete' or b.completion<>'complete' then
  return 'Incomplete run; absence cannot be assessed';
 end if;
 if jsonb_array_length(coalesce(r.envelope->'errors','[]'::jsonb))>0
  or jsonb_array_length(coalesce(r.envelope->'quarantine','[]'::jsonb))>0
  or jsonb_array_length(coalesce(b.envelope->'errors','[]'::jsonb))>0
  or jsonb_array_length(coalesce(b.envelope->'quarantine','[]'::jsonb))>0 then
  return 'Snapshot contains errors or quarantine';
 end if;
 if r.raw_removed_at is not null or b.raw_removed_at is not null then
  return 'Retained evidence was purged';
 end if;
 if not exists(select 1 from ingestion.complete_snapshot_sources q
  where q.source_id=r.source_id and q.resource_id=r.resource_id
   and q.scope is not distinct from ingestion.complete_snapshot_scope_key(r.envelope->'scope') and q.active) then
  return 'Source scope is not qualified as a complete snapshot';
 end if;
 return null;
end $$;

create function community_orgs.qualify_complete_snapshot_source(
 p_source text,p_resource text,p_scope jsonb,p_identity jsonb,p_note text
) returns void language plpgsql security definer set search_path='' as $$
begin
 if community_orgs.is_platform_admin() is distinct from true then raise exception 'Administrator required' using errcode='42501'; end if;
 if jsonb_typeof(p_scope) is distinct from 'object'
  or p_scope->>'complete_snapshot' is distinct from 'true'
  or coalesce(p_scope->>'kind','')<>'complete-snapshot'
  or coalesce(length(trim(p_scope->>'snapshot_series')),0)=0
  or p_scope ? 'filters'
  or jsonb_typeof(p_identity) is distinct from 'object'
  or p_identity->>'native_id_stable' is distinct from 'true'
  or coalesce(length(trim(p_identity->>'identity_basis')),0)=0
  or coalesce(length(trim(p_note)),0) not between 1 and 2000 then
  raise exception 'Complete snapshot scope, stable identity evidence and note required' using errcode='22023';
 end if;
 if not exists(select 1 from ingestion.sources where source_id=p_source and resource_id=p_resource) then
  raise exception 'Source not found' using errcode='P0002';
 end if;
 insert into ingestion.complete_snapshot_sources(source_id,resource_id,scope,identity,note,qualified_by)
 values(p_source,p_resource,ingestion.complete_snapshot_scope_key(p_scope),p_identity,trim(p_note),auth.uid())
 on conflict(source_id,resource_id,scope) do update set
  identity=excluded.identity,note=excluded.note,active=true,qualified_by=excluded.qualified_by,qualified_at=now();
end $$;

create function community_orgs.complete_snapshot_reconciliation_report(p_run text,p_baseline text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r ingestion.ingestion_runs; b ingestion.ingestion_runs; reason text; records jsonb;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 select * into r from ingestion.ingestion_runs where id=p_run::bigint;
 if not found then raise exception 'Run not found' using errcode='P0002'; end if;
 select * into b from ingestion.ingestion_runs where id=p_baseline::bigint;
 if not found then raise exception 'Baseline not found' using errcode='P0002'; end if;
 reason:=ingestion.reconciliation_missing_reason(r.id,b.id);
 if reason is not null then
  return jsonb_build_object('report_version','p27-v1','run_id',r.id::text,'baseline_run',b.id::text,
   'source_id',r.source_id,'resource_id',r.resource_id,'scope',r.envelope->'scope',
   'assessed',false,'reason',reason,'implies_deletion',false,'records','[]'::jsonb,
   'counts',jsonb_build_object('missing',0,'actioned',0));
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'native_id',s.native_id,'record_id',s.id::text,'baseline_run',b.id::text,
  'organisation_id',l.organisation_id,'organisation_name',o.entity_name,
  'current_public',o.is_public,'reason','Missing from a qualified complete snapshot; operator review required',
  'prior_version_id',v.id::text,'prior_payload',v.payload,
  'existing_actions',coalesce((select jsonb_agg(jsonb_build_object(
    'id',a.id,'action',a.action,'reason',a.reason,'approved_at',a.approved_at,'applied_at',a.applied_at,'result',a.result)
    order by a.approved_at) from ingestion.reconciliation_actions a
    where a.run_id=r.id and a.baseline_run_id=b.id and a.record_id=s.id),'[]'::jsonb)
 ) order by s.native_id),'[]'::jsonb) into records
 from ingestion.run_records rr
 join ingestion.source_record_versions v on v.id=rr.version_id
 join ingestion.source_records s on s.id=v.record_id
 join ingestion.source_links l on l.record_id=s.id and l.organisation_id is not null
 join community_orgs.organisations o on o.org_id=l.organisation_id
 where rr.run_id=b.id
  and not exists(select 1 from ingestion.run_records cr
   join ingestion.source_record_versions cv on cv.id=cr.version_id
   where cr.run_id=r.id and cv.record_id=s.id)
  and not exists(select 1 from jsonb_array_elements(coalesce(r.envelope->'quarantine','[]')) q where q->>'native_id'=s.native_id);
 return jsonb_build_object('report_version','p27-v1','run_id',r.id::text,'baseline_run',b.id::text,
  'source_id',r.source_id,'resource_id',r.resource_id,'scope',r.envelope->'scope',
  'assessed',true,'reason',null,'implies_deletion',false,'records',records,
  'counts',jsonb_build_object('missing',jsonb_array_length(records),
   'actioned',(select count(*) from ingestion.reconciliation_actions a where a.run_id=r.id and a.baseline_run_id=b.id)));
end $$;

create function community_orgs.approve_reconciliation_action(
 p_run text,p_baseline text,p_record text,p_action text,p_reason text,p_expected jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare r ingestion.ingestion_runs; b ingestion.ingestion_runs; s ingestion.source_records; org uuid; action_id uuid; reason text;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 if p_action not in ('closure','suppress','remove','no_action')
  or coalesce(length(trim(p_reason)),0) not between 1 and 2000
  or jsonb_typeof(p_expected) is distinct from 'object' then
  raise exception 'Valid action, reason and expected snapshot required' using errcode='22023';
 end if;
 select * into r from ingestion.ingestion_runs where id=p_run::bigint for share;
 if not found then raise exception 'Run not found' using errcode='P0002'; end if;
 select * into b from ingestion.ingestion_runs where id=p_baseline::bigint for share;
 if not found then raise exception 'Baseline not found' using errcode='P0002'; end if;
 reason:=ingestion.reconciliation_missing_reason(r.id,b.id);
 if reason is not null then raise exception '%',reason using errcode='22023'; end if;
 select * into s from ingestion.source_records where id=p_record::bigint;
 if not found then raise exception 'Source record not found' using errcode='P0002'; end if;
 if (s.source_id,s.resource_id) is distinct from (r.source_id,r.resource_id) then raise exception 'Record is not in source scope' using errcode='22023'; end if;
 if not exists(select 1 from ingestion.run_records rr join ingestion.source_record_versions v on v.id=rr.version_id
  where rr.run_id=b.id and v.record_id=s.id)
  or exists(select 1 from ingestion.run_records rr join ingestion.source_record_versions v on v.id=rr.version_id
  where rr.run_id=r.id and v.record_id=s.id) then
  raise exception 'Record is not a current missing candidate' using errcode='40001';
 end if;
 select organisation_id into org from ingestion.source_links where record_id=s.id;
 if org is null then raise exception 'Linked organisation required' using errcode='22023'; end if;
 if p_expected->>'run_id' is distinct from r.id::text
  or p_expected->>'baseline_run' is distinct from b.id::text
  or p_expected->>'record_id' is distinct from s.id::text
  or p_expected->>'organisation_id' is distinct from org::text
  or p_expected->'scope' is distinct from r.envelope->'scope' then
  raise exception 'Candidate changed; reload reconciliation report' using errcode='40001';
 end if;
 lock table community_orgs.organisations,community_orgs.acnc_register_details in share row exclusive mode;
 insert into ingestion.reconciliation_actions(run_id,baseline_run_id,record_id,organisation_id,action,reason,expected,approved_by)
 values(r.id,b.id,s.id,org,p_action,trim(p_reason),p_expected,auth.uid())
 returning id into action_id;
 if p_action in ('closure','suppress','remove') then
  insert into ingestion.suppressions(record_id,field,organisation_id,reason,suppressed_by)
  values(s.id,'*',org,'Reconciliation '||p_action||': '||trim(p_reason),auth.uid())
  on conflict do nothing;
  update community_orgs.acnc_register_details set is_public=false where org_id=org;
  if p_action in ('closure','remove') then update community_orgs.organisations set is_public=false where org_id=org; end if;
 end if;
 update ingestion.reconciliation_actions set applied_at=now(),result=jsonb_build_object(
  'organisation_id',org,'action',p_action,'organisation_public',(select is_public from community_orgs.organisations where org_id=org),
  'suppression_recorded',exists(select 1 from ingestion.suppressions where record_id=s.id and field='*' and organisation_id=org))
 where id=action_id;
 return action_id;
end $$;

revoke all on function ingestion.reconciliation_missing_reason(bigint,bigint) from public,anon,authenticated,service_role,ingestion_worker;
revoke all on function ingestion.complete_snapshot_scope_key(jsonb) from public,anon,authenticated,service_role,ingestion_worker;
revoke all on function community_orgs.qualify_complete_snapshot_source(text,text,jsonb,jsonb,text),
 community_orgs.complete_snapshot_reconciliation_report(text,text),
 community_orgs.approve_reconciliation_action(text,text,text,text,text,jsonb) from public,anon,service_role,ingestion_worker;
grant execute on function community_orgs.qualify_complete_snapshot_source(text,text,jsonb,jsonb,text),
 community_orgs.complete_snapshot_reconciliation_report(text,text),
 community_orgs.approve_reconciliation_action(text,text,text,text,text,jsonb) to authenticated;
