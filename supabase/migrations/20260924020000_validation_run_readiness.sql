create function community_orgs.validation_run_readiness(p_run text) returns jsonb
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
 active ingestion.validation_replays;
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
 select * into active from ingestion.validation_replays
 where parent_run_id=parent.id and status in ('queued','running')
 order by requested_at desc limit 1;
 eligible:=parent.raw_removed_at is null and acquisition_count=0 and issue_count>0
  and unresolved_count=0 and non_overridable_count=0 and deferred_count=0 and rejected_count=0
  and active.id is null;

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
  'active_replay',case when active.id is null then null else jsonb_build_object(
   'id',active.id,'status',active.status,'requested_at',active.requested_at,'message',active.message
  ) end
 );
end $$;

revoke all on function community_orgs.validation_run_readiness(text)
 from public,anon,service_role,ingestion_worker;
grant execute on function community_orgs.validation_run_readiness(text) to authenticated;
