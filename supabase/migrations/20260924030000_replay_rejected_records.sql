-- A reject_record decision is terminal and replay-compatible: the operator has
-- intentionally excluded that source record. It is not quarantine and must be
-- carried as explicit immutable replay evidence.

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
  and unresolved_count=0 and non_overridable_count=0 and deferred_count=0
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

create or replace function community_orgs.create_corrected_run(p_run text) returns text
language plpgsql security definer set search_path='' as $$
declare parent ingestion.ingestion_runs; snapshot jsonb; replay uuid;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 select * into parent from ingestion.ingestion_runs where id=p_run::bigint for share;
 if not found then raise exception 'Run not found' using errcode='P0002'; end if;
 if parent.raw_removed_at is not null then raise exception 'Raw evidence expired' using errcode='22023'; end if;
 if jsonb_array_length(coalesce(parent.envelope->'errors','[]'))>0 then raise exception 'Acquisition failures require a new acquisition' using errcode='22023'; end if;
 if not exists(select 1 from ingestion.validation_issues where ingestion_run_id=parent.id) then
  raise exception 'No validation issues exist for this run' using errcode='22023'; end if;
 if exists(select 1 from ingestion.validation_issues i left join ingestion.validation_resolutions r on r.issue_id=i.id
  where i.ingestion_run_id=parent.id and i.severity='blocking' and
   (not ingestion.validation_category_overridable(i.category) or r.issue_id is null or r.decision='defer')) then
  raise exception 'Blocking issues remain unresolved or non-overridable' using errcode='22023'; end if;
 select jsonb_agg(jsonb_build_object('issue_id',i.id::text,'revision',r.revision,'decision',r.decision,
  'native_id',i.subject_native_id,'row',i.source_row,'source_key',i.source_key,'canonical_key',i.canonical_key,
  'source_value',i.source_value,'raw_evidence_hash',i.raw_evidence_hash,'proposed_value',r.proposed_value,
  'canonical_value',r.canonical_value,'validator_name',coalesce(r.validator_name,i.validator_name),
  'validator_version',coalesce(r.validator_version,i.validator_version)) order by i.id)
 into snapshot from ingestion.validation_issues i join ingestion.validation_resolutions r on r.issue_id=i.id
 where i.ingestion_run_id=parent.id;
 insert into ingestion.validation_replays(parent_run_id,resolution_revisions,requested_by)
 values(parent.id,snapshot,auth.uid()) returning id into replay;
 return replay::text;
exception when unique_violation then raise exception 'A corrected run is already queued' using errcode='40001';
end $$;

create or replace function ingestion.finish_validation_replay(p_replay uuid,p_token uuid,p_envelope jsonb) returns bigint
language plpgsql security definer set search_path='' as $$
declare replay ingestion.validation_replays; parent ingestion.ingestion_runs; derived bigint;
 expected jsonb; expected_rejections jsonb; expected_scope jsonb;
begin
 select * into replay from ingestion.validation_replays where id=p_replay for update;
 if not found or replay.status<>'running' or replay.lease_token is distinct from p_token or replay.lease_until<=now()
  then raise exception 'Replay lease lost' using errcode='40001'; end if;
 select * into parent from ingestion.ingestion_runs where id=replay.parent_run_id for share;
 select jsonb_agg(jsonb_build_object('issue_id',i.id::text,'revision',r.revision,'decision',r.decision,
  'native_id',i.subject_native_id,'row',i.source_row,'source_key',i.source_key,'canonical_key',i.canonical_key,
  'source_value',i.source_value,'raw_evidence_hash',i.raw_evidence_hash,'proposed_value',r.proposed_value,
  'canonical_value',r.canonical_value,'validator_name',coalesce(r.validator_name,i.validator_name),
  'validator_version',coalesce(r.validator_version,i.validator_version)) order by i.id) into expected
 from ingestion.validation_issues i join ingestion.validation_resolutions r on r.issue_id=i.id where i.ingestion_run_id=parent.id;
 select coalesce(jsonb_agg(jsonb_build_object(
  'issue_id',i.id::text,'revision',r.revision,'native_id',i.subject_native_id,'row',i.source_row
 ) order by i.id),'[]'::jsonb) into expected_rejections
 from ingestion.validation_issues i join ingestion.validation_resolutions r on r.issue_id=i.id
 where i.ingestion_run_id=parent.id and r.decision='reject_record';
 expected_scope:=case when jsonb_array_length(expected_rejections)>0
  then jsonb_set(parent.envelope->'scope','{complete_snapshot}','false'::jsonb,true)
  else parent.envelope->'scope' end;
 if expected is distinct from replay.resolution_revisions or parent.raw_removed_at is not null
  or p_envelope->>'run_id' is distinct from 'validation-replay-'||replay.id::text
  or p_envelope->>'source_id' is distinct from parent.source_id or p_envelope->>'resource_id' is distinct from parent.resource_id
  or p_envelope->'observed_at' is distinct from parent.envelope->'observed_at'
  or p_envelope->'scope' is distinct from expected_scope
  or p_envelope->'qualification' is distinct from parent.envelope->'qualification'
  or p_envelope->'pages' is distinct from parent.envelope->'pages'
  or coalesce(p_envelope->'validation_replay'->'rejections','[]'::jsonb) is distinct from expected_rejections
  or p_envelope->'errors' is distinct from '[]'::jsonb or p_envelope->>'completion'<>'complete'
  or jsonb_array_length(coalesce(p_envelope->'quarantine','[]'))<>0
  or p_envelope->'publication_eligible' is distinct from 'false'::jsonb
  then raise exception 'Derived run does not preserve replay evidence or pass all gates' using errcode='22023'; end if;
 if parent.source_id='acnc-register' then derived:=ingestion.stage_acnc(p_envelope);
 elsif parent.envelope->>'parser_version'='approved-csv-v1' then derived:=ingestion.stage_csv(p_envelope);
 else raise exception 'No qualified replay adapter for source' using errcode='22023'; end if;
 insert into ingestion.reprocessing_runs(run_id,parent_run_id,processed_at,mapping_version)
 values(derived,parent.id,now(),p_envelope->>'mapping_version') on conflict do nothing;
 update ingestion.validation_replays set status='complete',derived_run_id=derived,finished_at=now(),lease_token=null,
  lease_until=null,message='Corrected private run created; intentional record rejections retained in replay evidence.' where id=replay.id;
 return derived;
end $$;

revoke all on function community_orgs.validation_run_readiness(text),
 community_orgs.create_corrected_run(text) from public,anon,service_role,ingestion_worker;
grant execute on function community_orgs.validation_run_readiness(text),
 community_orgs.create_corrected_run(text) to authenticated;
revoke all on function ingestion.finish_validation_replay(uuid,uuid,jsonb)
 from public,anon,authenticated,service_role;
grant execute on function ingestion.finish_validation_replay(uuid,uuid,jsonb) to ingestion_worker;
