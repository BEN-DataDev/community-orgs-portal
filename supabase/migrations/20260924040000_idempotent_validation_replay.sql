create function ingestion.validation_resolution_snapshot(p_run bigint) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_agg(jsonb_build_object(
  'issue_id',i.id::text,'revision',r.revision,'decision',r.decision,
  'native_id',i.subject_native_id,'row',i.source_row,'source_key',i.source_key,
  'canonical_key',i.canonical_key,'source_value',i.source_value,
  'raw_evidence_hash',i.raw_evidence_hash,'proposed_value',r.proposed_value,
  'canonical_value',r.canonical_value,'validator_name',coalesce(r.validator_name,i.validator_name),
  'validator_version',coalesce(r.validator_version,i.validator_version)
 ) order by i.id)
 from ingestion.validation_issues i
 join ingestion.validation_resolutions r on r.issue_id=i.id
 where i.ingestion_run_id=p_run
$$;
revoke all on function ingestion.validation_resolution_snapshot(bigint)
 from public,anon,authenticated,service_role,ingestion_worker;

create or replace function community_orgs.validation_run_readiness(p_run text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 parent ingestion.ingestion_runs;
 issue_count bigint;
 blocking_count bigint;
 unresolved_count bigint;
 non_overridable_count bigint;
 deferred_count bigint;
 rejected_count bigint;
 acquisition_count integer;
 existing ingestion.validation_replays;
 snapshot jsonb;
 eligible boolean;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then
  raise exception 'Operator required' using errcode='42501';
 end if;
 select * into parent from ingestion.ingestion_runs where id=p_run::bigint;
 if not found then raise exception 'Run not found' using errcode='P0002'; end if;

 select count(*),
  count(*) filter(where i.severity='blocking'),
  count(*) filter(where i.severity='blocking' and ingestion.validation_category_overridable(i.category) and r.issue_id is null),
  count(*) filter(where i.severity='blocking' and not ingestion.validation_category_overridable(i.category)),
  count(*) filter(where i.severity='blocking' and r.decision='defer'),
  count(*) filter(where i.severity='blocking' and r.decision='reject_record')
 into issue_count,blocking_count,unresolved_count,non_overridable_count,deferred_count,rejected_count
 from ingestion.validation_issues i
 left join ingestion.validation_resolutions r on r.issue_id=i.id
 where i.ingestion_run_id=parent.id;

 acquisition_count:=jsonb_array_length(coalesce(parent.envelope->'errors','[]'::jsonb));
 snapshot:=ingestion.validation_resolution_snapshot(parent.id);
 select * into existing from ingestion.validation_replays
 where parent_run_id=parent.id and resolution_revisions=snapshot
  and status in ('queued','running','complete')
 order by case status when 'queued' then 1 when 'running' then 2 else 3 end,requested_at desc limit 1;
 eligible:=parent.raw_removed_at is null and acquisition_count=0 and issue_count>0
  and unresolved_count=0 and non_overridable_count=0 and deferred_count=0
  and existing.id is null;

 return jsonb_build_object(
  'run_id',parent.id::text,
  'eligible',eligible,
  'raw_evidence_available',parent.raw_removed_at is null,
  'issue_count',issue_count,
  'blocking_count',blocking_count,
  'unresolved_blocking_count',unresolved_count,
  'non_overridable_blocking_count',non_overridable_count,
  'deferred_blocking_count',deferred_count,
  'rejected_blocking_count',rejected_count,
  'acquisition_failure_count',acquisition_count,
  'active_replay',case when existing.id is null then null else jsonb_build_object(
   'id',existing.id,'status',existing.status,'requested_at',existing.requested_at,
   'message',existing.message,'derived_run_id',existing.derived_run_id::text
  ) end
 );
end $$;

create or replace function community_orgs.create_corrected_run(p_run text) returns text
language plpgsql security definer set search_path='' as $$
declare parent ingestion.ingestion_runs; snapshot jsonb; replay uuid; existing ingestion.validation_replays;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 select * into parent from ingestion.ingestion_runs where id=p_run::bigint for share;
 if not found then raise exception 'Run not found' using errcode='P0002'; end if;
 perform pg_catalog.pg_advisory_xact_lock(parent.id);
 if parent.raw_removed_at is not null then raise exception 'Raw evidence expired' using errcode='22023'; end if;
 if jsonb_array_length(coalesce(parent.envelope->'errors','[]'))>0 then raise exception 'Acquisition failures require a new acquisition' using errcode='22023'; end if;
 if not exists(select 1 from ingestion.validation_issues where ingestion_run_id=parent.id) then
  raise exception 'No validation issues exist for this run' using errcode='22023'; end if;
 if exists(select 1 from ingestion.validation_issues i left join ingestion.validation_resolutions r on r.issue_id=i.id
  where i.ingestion_run_id=parent.id and i.severity='blocking' and
   (not ingestion.validation_category_overridable(i.category) or r.issue_id is null or r.decision='defer')) then
  raise exception 'Blocking issues remain unresolved or non-overridable' using errcode='22023'; end if;
 snapshot:=ingestion.validation_resolution_snapshot(parent.id);
 select * into existing from ingestion.validation_replays
 where parent_run_id=parent.id and resolution_revisions=snapshot
  and status in ('queued','running','complete')
 order by case status when 'queued' then 1 when 'running' then 2 else 3 end,requested_at desc limit 1;
 if existing.id is not null then
  if existing.status='complete' then
   raise exception 'A corrected run already completed for these resolutions' using errcode='40001';
  end if;
  raise exception 'A corrected run is already queued' using errcode='40001';
 end if;
 insert into ingestion.validation_replays(parent_run_id,resolution_revisions,requested_by)
 values(parent.id,snapshot,auth.uid()) returning id into replay;
 return replay::text;
end $$;

revoke all on function community_orgs.validation_run_readiness(text),
 community_orgs.create_corrected_run(text) from public,anon,service_role,ingestion_worker;
grant execute on function community_orgs.validation_run_readiness(text),
 community_orgs.create_corrected_run(text) to authenticated;
