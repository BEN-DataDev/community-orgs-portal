-- P15: private read-only batch evidence. Approval snapshots remain unchanged.
create function community_orgs.ingestion_change_report(p_run text, p_baseline text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r ingestion.ingestion_runs; b ingestion.ingestion_runs; rec record;
 rv ingestion.reviews; prior record; matched jsonb; target uuid; preview jsonb; fields jsonb;
 records jsonb:='[]'; status text; missing_reason text; counts jsonb; item jsonb;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then
  raise exception 'Operator required' using errcode='42501'; end if;
 select * into r from ingestion.ingestion_runs where id=p_run::bigint;
 if not found then raise exception 'Run not found' using errcode='P0002'; end if;
 if p_baseline is not null then
  select * into b from ingestion.ingestion_runs where id=p_baseline::bigint;
  if not found then raise exception 'Baseline not found' using errcode='P0002'; end if;
  if (b.source_id,b.resource_id) is distinct from (r.source_id,r.resource_id)
   or b.id=r.id or b.observed_at>=r.observed_at
   or b.envelope->'scope' is distinct from r.envelope->'scope'
   or coalesce(r.envelope->'scope','{}') in ('{}'::jsonb,'null'::jsonb) then
   raise exception 'Baseline must be an earlier observation of the same source, resource and explicit scope' using errcode='22023'; end if;
 end if;
 missing_reason:=case when p_baseline is null then 'No baseline selected'
  when r.completion<>'complete' or b.completion<>'complete' then 'Incomplete run; absence cannot be assessed'
  when r.raw_removed_at is not null or b.raw_removed_at is not null then 'Retained evidence was purged'
  else null end;
 for rec in select v.*,s.native_id from ingestion.run_records rr
  join ingestion.source_record_versions v on v.id=rr.version_id
  join ingestion.source_records s on s.id=v.record_id where rr.run_id=r.id order by s.native_id,v.id
 loop
  select * into rv from ingestion.reviews where version_id=rec.id;
  matched:=ingestion.match_identity(rec.id);
  target:=case when rv.decision='create' then null
   else coalesce(rv.organisation_id,(matched->>'organisation_id')::uuid) end;
  preview:=community_orgs.ingestion_field_preview(p_run,rec.id::text,target);
  -- Prior observation, not prior sequence ID: unchanged replays reuse versions.
  select i.id as run_id,i.observed_at,v.id as version_id,v.payload,v.parser_version,v.content_hash into prior
   from ingestion.run_records rr join ingestion.ingestion_runs i on i.id=rr.run_id
   join ingestion.source_record_versions v on v.id=rr.version_id
   where v.record_id=rec.record_id and i.observed_at<r.observed_at
    and i.envelope->'scope' is not distinct from r.envelope->'scope'
   order by i.observed_at desc,i.id desc,v.id desc limit 1;
  select coalesce(jsonb_agg(f || jsonb_build_object(
   'prior_source', (select jsonb_build_object('present',true,'value',a.value) from ingestion.field_assertions a
    where a.version_id=prior.version_id and a.field=f->>'field'),
   'publication_history',coalesce((select jsonb_agg(jsonb_build_object(
    'change_set_id',p.change_set_id,'published_at',p.published_at,'organisation_id',p.organisation_id,
    'source_version',c.version_id::text,'approved_revision',approved->>'revision','change',change)
    order by p.published_at,c.id)
    from ingestion.publications p join ingestion.change_sets c on c.id=p.change_set_id
    join ingestion.source_record_versions v on v.id=c.version_id
    cross join lateral jsonb_array_elements(p.changes) change
    cross join lateral jsonb_array_elements(c.fields) approved
    where v.record_id=rec.record_id and change->>'field'=f->>'field'
     and approved->>'field'=f->>'field'),'[]'::jsonb)) order by f->>'field'),'[]') into fields
   from jsonb_array_elements(preview->'fields') f;
  status:=case when rv.decision='reject' then 'rejected'
   when matched->>'status'='hold' or (matched->>'organisation_id' is not null
    and (rv.decision='create' or target is distinct from (matched->>'organisation_id')::uuid)) then 'conflicting'
   when exists(select 1 from jsonb_array_elements(fields) f where f->>'status' in ('conflict','ambiguous','invalid','suppressed')) then 'conflicting'
   when target is null then 'new'
   when exists(select 1 from jsonb_array_elements(fields) f where f->>'status' in ('new','changed')) then 'changed'
   else 'unchanged' end;
  records:=records || jsonb_build_array(jsonb_build_object('native_id',rec.native_id,
   'version_id',rec.id::text,'record_id',rec.record_id::text,'status',status,'identity_match',matched,
   'organisation_id',target,'review',to_jsonb(rv),'fields',fields,
   'evidence',jsonb_build_object('parser_version',rec.parser_version,'content_hash',rec.content_hash,
    'payload',rec.payload,'observed_at',r.observed_at),
   'prior_observation',case when prior.run_id is null then null else jsonb_build_object(
    'run_id',prior.run_id::text,'version_id',prior.version_id::text,'observed_at',prior.observed_at,
    'parser_version',prior.parser_version,'content_hash',prior.content_hash,'payload',prior.payload) end,
   'review_history',coalesce((select jsonb_agg(to_jsonb(e) order by e.revision)
    from ingestion.review_events e where e.version_id=rec.id),'[]')));
 end loop;
 for item in select value from jsonb_array_elements(coalesce(r.envelope->'quarantine','[]')) loop
  records:=records || jsonb_build_array(jsonb_build_object('native_id',coalesce(item->>'native_id',
   nullif(btrim(item->'raw'->>'source_record_id'),''),item->'raw'->>'_id'),
   'status','rejected','rejection_kind','quarantined','reason',item->>'reason','evidence',item,'fields','[]'::jsonb));
 end loop;
 if missing_reason is null then
  for rec in select s.native_id,v.* from ingestion.run_records rr
   join ingestion.source_record_versions v on v.id=rr.version_id
   join ingestion.source_records s on s.id=v.record_id where rr.run_id=b.id
   and not exists(select 1 from ingestion.run_records current_rr join ingestion.source_record_versions cv on cv.id=current_rr.version_id
    where current_rr.run_id=r.id and cv.record_id=v.record_id)
   and not exists(select 1 from jsonb_array_elements(coalesce(r.envelope->'quarantine','[]')) q where q->>'native_id'=s.native_id)
   order by s.native_id
  loop
   records:=records || jsonb_build_array(jsonb_build_object('native_id',rec.native_id,'status','missing',
    'record_id',rec.record_id::text,'baseline_run',b.id::text,'version_id',rec.id::text,
    'reason','Not observed in selected run; no deletion or withdrawal inferred',
    'evidence',rec.payload,'fields','[]'::jsonb));
  end loop;
 end if;
 select jsonb_object_agg(s,(select count(*) from jsonb_array_elements(records) x where x->>'status'=s)) into counts
  from unnest(array['new','unchanged','changed','conflicting','rejected','missing']) s;
 return jsonb_build_object('report_version','p15-v1','run_id',r.id::text,'run_key',r.run_key,
  'source_id',r.source_id,'resource_id',r.resource_id,'observed_at',r.observed_at,
  'completion',r.completion,'raw_evidence_removed',r.raw_removed_at is not null,'scope',r.envelope->'scope','baseline_run',b.id::text,
  'missing_assessment',jsonb_build_object('assessed',missing_reason is null,'reason',missing_reason,'implies_deletion',false),
  'errors',coalesce(r.envelope->'errors','[]'),'counts',counts,'records',records);
end $$;
revoke all on function community_orgs.ingestion_change_report(text,text) from public,anon,service_role,ingestion_worker;
grant execute on function community_orgs.ingestion_change_report(text,text) to authenticated;
