-- Offline replay lineage. Existing evidence, reviews, links and approvals are immutable here.
create table ingestion.reprocessing_runs (
 run_id bigint primary key references ingestion.ingestion_runs,
 parent_run_id bigint not null references ingestion.ingestion_runs,
 processed_at timestamptz not null,
 mapping_version text not null,
 check (run_id <> parent_run_id)
);
alter table ingestion.reprocessing_runs enable row level security;
revoke all on ingestion.reprocessing_runs from public,anon,authenticated,service_role,ingestion_worker;

create function ingestion.stage_acnc_reprocessing(p_parent bigint,p_envelope jsonb)
returns bigint language plpgsql security definer set search_path='' as $$
declare parent ingestion.ingestion_runs; r jsonb; old jsonb; run bigint; seen text[]:='{}';
 meta jsonb:=p_envelope->'reprocessing'; quarantined boolean;
begin
 select * into parent from ingestion.ingestion_runs where id=p_parent for share;
 if not found or parent.completion<>'complete' then raise exception 'Complete parent acquisition required'; end if;
 if meta->>'parent_run_id' is distinct from p_parent::text
  or meta->>'parent_run_key' is distinct from parent.run_key
  or meta->>'parent_parser_version' is distinct from parent.envelope->>'parser_version'
  or coalesce(meta->>'processed_at','')=''
  or meta->>'mapping_version' is distinct from 'acnc-register-fields-v2'
  or p_envelope->>'parser_version' is distinct from 'acnc-ckan-v2'
  or p_envelope->>'parser_version' is not distinct from parent.envelope->>'parser_version'
  or p_envelope->>'run_id' is not distinct from parent.run_key
  or p_envelope->>'source_id' is distinct from parent.source_id
  or p_envelope->>'resource_id' is distinct from parent.resource_id
  or p_envelope->'observed_at' is distinct from parent.envelope->'observed_at'
  or p_envelope->'scope' is distinct from parent.envelope->'scope'
  or p_envelope->'pages' is distinct from parent.envelope->'pages'
  or p_envelope->'qualification' is distinct from parent.envelope->'qualification'
  or p_envelope->'synthetic' is distinct from parent.envelope->'synthetic'
  or p_envelope->'errors' is distinct from '[]'::jsonb
  or jsonb_typeof(p_envelope->'records') is distinct from 'array'
  or jsonb_typeof(p_envelope->'quarantine') is distinct from 'array'
 then raise exception 'Replay metadata must preserve parent acquisition evidence'; end if;
 for r,quarantined in
  select value,false from jsonb_array_elements(p_envelope->'records')
  union all select value,true from jsonb_array_elements(p_envelope->'quarantine')
 loop
  if coalesce(r->>'native_id','')='' or r->>'native_id'=any(seen) then raise exception 'Duplicate/missing replay identity'; end if;
  seen:=array_append(seen,r->>'native_id');
  select value into old from jsonb_array_elements(parent.envelope->'records') where value->>'native_id'=r->>'native_id';
  if not found or r->'raw' is distinct from old->'raw'
   or r->>'raw_sha256' is distinct from old->>'raw_sha256'
   or r->'raw'->>'_id' is distinct from r->>'native_id'
   or not exists(select 1 from ingestion.run_records rr join ingestion.source_record_versions v on v.id=rr.version_id
    join ingestion.source_records sr on sr.id=v.record_id
    where rr.run_id=p_parent and sr.source_id=parent.source_id and sr.resource_id=parent.resource_id
     and sr.native_id=r->>'native_id' and v.payload->'raw'=r->'raw'
     and v.payload->>'raw_sha256'=r->>'raw_sha256')
  then raise exception 'Replay identity or evidence differs from retained version'; end if;
  if quarantined then
   if coalesce(r->>'reason','')='' then raise exception 'Quarantine reason required'; end if;
  elsif r->'source_url' is distinct from old->'source_url'
   or r->'source_modified_at' is distinct from old->'source_modified_at'
   or r->>'mapping_version' is distinct from meta->>'mapping_version' then
   raise exception 'Replay source metadata changed';
  end if;
 end loop;
 if cardinality(seen)<>jsonb_array_length(parent.envelope->'records')
  or (p_envelope->'counts'->>'accepted')::integer is distinct from jsonb_array_length(p_envelope->'records')
  or (p_envelope->'counts'->>'quarantined')::integer is distinct from jsonb_array_length(p_envelope->'quarantine')
  or p_envelope->'counts'->'source_total' is distinct from parent.envelope->'counts'->'source_total'
  or p_envelope->'counts'->'pages' is distinct from parent.envelope->'counts'->'pages'
  or p_envelope->>'completion' is distinct from (case when jsonb_array_length(p_envelope->'quarantine')=0 then 'complete' else 'partial' end)
 then raise exception 'Replay must account for every original record'; end if;
 run:=ingestion.stage_acnc(p_envelope);
 insert into ingestion.reprocessing_runs values(run,p_parent,(meta->>'processed_at')::timestamptz,meta->>'mapping_version')
 on conflict(run_id) do nothing;
 return run;
end $$;
revoke all on function ingestion.stage_acnc_reprocessing(bigint,jsonb) from public,anon,authenticated,service_role;
grant execute on function ingestion.stage_acnc_reprocessing(bigint,jsonb) to ingestion_worker;

-- Preserve the queue contract while making validated existing links the default preview target.
alter function community_orgs.ingestion_review_queue(text,text,integer,text) rename to ingestion_review_queue_before_reprocessing;
revoke all on function community_orgs.ingestion_review_queue_before_reprocessing(text,text,integer,text) from public,anon,authenticated,service_role;
create function community_orgs.ingestion_review_queue(p_run text default null,p_version text default null,p_offset integer default 0,p_search text default '')
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; linked uuid; replay jsonb;
begin
 result:=community_orgs.ingestion_review_queue_before_reprocessing(p_run,p_version,p_offset,p_search);
 select jsonb_build_object('parent_run_id',r.parent_run_id::text,'processed_at',r.processed_at,
  'quarantined',jsonb_array_length(i.envelope->'quarantine')) into replay
 from ingestion.reprocessing_runs r join ingestion.ingestion_runs i on i.id=r.run_id where r.run_id=(result->>'run')::bigint;
 result:=result || jsonb_build_object('reprocessing',replay);
 if result->'detail'<>'null'::jsonb then
  select l.organisation_id into linked from ingestion.source_record_versions v
   join ingestion.source_links l on l.record_id=v.record_id where v.id=(result->'detail'->>'id')::bigint;
  result:=jsonb_set(result,'{detail}',result->'detail' || jsonb_build_object('linked_organisation_id',linked));
 end if;
 return result;
end $$;
revoke all on function community_orgs.ingestion_review_queue(text,text,integer,text) from public,anon;
grant execute on function community_orgs.ingestion_review_queue(text,text,integer,text) to authenticated;

create function community_orgs.ingestion_reprocessing_report(p_run text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rec record; fields jsonb; records jsonb:='[]'; r ingestion.ingestion_runs;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 select * into r from ingestion.ingestion_runs where id=p_run::bigint;
 if not found then raise exception 'Run not found' using errcode='P0002'; end if;
 for rec in select v.id,s.native_id,v.record_id,coalesce(rv.organisation_id,l.organisation_id) as org
  from ingestion.run_records rr join ingestion.source_record_versions v on v.id=rr.version_id
  join ingestion.source_records s on s.id=v.record_id
  left join ingestion.reviews rv on rv.version_id=v.id left join ingestion.source_links l on l.record_id=v.record_id
  where rr.run_id=r.id order by s.native_id
 loop
  select jsonb_agg(jsonb_build_object('field',f->>'field','status',f->>'status',
   'suppressed',f->>'status'='suppressed',
   'approved',exists(select 1 from ingestion.change_sets c where c.run_id=r.id and c.version_id=rec.id and c.fields @> jsonb_build_array(jsonb_build_object('field',f->>'field'))),
   'published',exists(select 1 from ingestion.change_sets c join ingestion.publications p on p.change_set_id=c.id
    where c.run_id=r.id and c.version_id=rec.id and p.changes @> jsonb_build_array(jsonb_build_object('field',f->>'field'))),
   'previously_published',exists(select 1 from ingestion.change_sets c join ingestion.publications p on p.change_set_id=c.id
    join ingestion.source_record_versions v on v.id=c.version_id where v.record_id=rec.record_id and c.run_id<>r.id
     and p.changes @> jsonb_build_array(jsonb_build_object('field',f->>'field'))))) into fields
  from jsonb_array_elements(community_orgs.ingestion_field_preview(p_run,rec.id::text,rec.org)->'fields') f;
  records:=records || jsonb_build_array(jsonb_build_object('native_id',rec.native_id,'fields',fields));
 end loop;
 return jsonb_build_object('run_id',p_run,'run_key',r.run_key,'source_id',r.source_id,'resource_id',r.resource_id,'completion',r.completion,'records',records,
  'quarantined',jsonb_array_length(r.envelope->'quarantine'));
end $$;
revoke all on function community_orgs.ingestion_reprocessing_report(text) from public,anon;
grant execute on function community_orgs.ingestion_reprocessing_report(text) to authenticated;
