-- P28: targeted retained-evidence redaction for suppression/withdrawal.
-- This removes suppressed pilot fields from private raw copies and worker
-- checkpoints while preserving source identity, hashes and private audit events.
create table ingestion.retained_evidence_redaction_events (
 id bigint generated always as identity primary key,
 source_id text not null,
 resource_id text not null,
 native_id text not null,
 record_id bigint not null references ingestion.source_records,
 field text not null check(field='*' or length(trim(field)) between 1 and 200),
 organisation_id uuid,
 reason text not null,
 suppressed_by uuid,
 redacted_at timestamptz not null default now(),
 database_actor text not null default session_user,
 version_count integer not null,
 assertion_count integer not null,
 run_count integer not null,
 checkpoint_count integer not null,
 approval_count integer not null,
 publication_count integer not null
);
alter table ingestion.retained_evidence_redaction_events enable row level security;
revoke all on ingestion.retained_evidence_redaction_events
 from public,anon,authenticated,service_role,ingestion_worker;
revoke all on sequence ingestion.retained_evidence_redaction_events_id_seq
 from public,anon,authenticated,service_role,ingestion_worker;

create function ingestion.redacted_acnc_raw_keys(p_record jsonb,p_field text) returns text[]
language sql immutable set search_path='' as $$
 select coalesce(array_agg(distinct k),'{}'::text[]) from (
  select jsonb_object_keys(a->'source_values') as k
  from jsonb_array_elements(coalesce(p_record->'assertions','[]'::jsonb)) a
  where a->>'field'=p_field and jsonb_typeof(a->'source_values')='object'
  union all select unnest(case p_field when 'abn' then array['ABN']
   when 'website' then array['Charity_Website']
   when 'entity_name' then array['Charity_Legal_Name']
   else array[]::text[] end)
 ) keys
$$;
revoke all on function ingestion.redacted_acnc_raw_keys(jsonb,text)
 from public,anon,authenticated,service_role,ingestion_worker;

create function ingestion.acnc_record_copy_needs_redaction(p_record jsonb,p_field text)
returns boolean language sql immutable set search_path='' as $$
 select case
  when p_field='*' then coalesce(p_record->'raw'->>'retained_evidence_redaction_scope','')<>'record'
   or coalesce(jsonb_array_length(p_record->'assertions'),0)>0
  when p_field<>'*' then exists(
    select 1 from unnest(ingestion.redacted_acnc_raw_keys(p_record,p_field)) k
    where coalesce(p_record->'raw','{}'::jsonb) ? k)
   or exists(select 1 from jsonb_array_elements(coalesce(p_record->'assertions','[]'::jsonb)) a
    where a->>'field'=p_field)
  else false end
$$;
revoke all on function ingestion.acnc_record_copy_needs_redaction(jsonb,text)
 from public,anon,authenticated,service_role,ingestion_worker;

create function ingestion.redact_acnc_record_copy(p_record jsonb,p_field text)
returns jsonb language plpgsql immutable set search_path='' as $$
declare raw jsonb; assertions jsonb; redacted jsonb; native text;
begin
 if not ingestion.acnc_record_copy_needs_redaction(p_record,p_field) then
  return p_record;
 end if;
 native := coalesce(p_record->'raw'->>'_id',p_record->>'native_id');
 if p_field='*' then
  return jsonb_set(jsonb_set(p_record,'{raw}',jsonb_strip_nulls(jsonb_build_object(
   '_id',native,'retained_evidence_redacted',true,'retained_evidence_redaction_scope','record')),true),
   '{assertions}','[]'::jsonb,true);
 end if;
 raw := coalesce(p_record->'raw','{}'::jsonb);
 select coalesce(raw - array_agg(k),raw) into raw
 from unnest(ingestion.redacted_acnc_raw_keys(p_record,p_field)) k;
 select coalesce(jsonb_agg(distinct f),'[]'::jsonb) into redacted
 from (select value f from jsonb_array_elements(coalesce(raw->'retained_evidence_redacted_fields','[]'::jsonb))
  union all select to_jsonb(p_field)) x;
 raw := raw || jsonb_build_object('retained_evidence_redacted',true,
  'retained_evidence_redacted_fields',redacted);
 select coalesce(jsonb_agg(a order by ord),'[]'::jsonb) into assertions
 from jsonb_array_elements(coalesce(p_record->'assertions','[]'::jsonb)) with ordinality x(a,ord)
 where a->>'field'<>p_field;
 return jsonb_set(jsonb_set(p_record,'{raw}',raw,true),'{assertions}',assertions,true);
end $$;
revoke all on function ingestion.redact_acnc_record_copy(jsonb,text)
 from public,anon,authenticated,service_role,ingestion_worker;

create function ingestion.redact_acnc_record_array(p_records jsonb,p_native text,p_field text)
returns jsonb language sql immutable set search_path='' as $$
 select coalesce(jsonb_agg(case
  when coalesce(x.value->>'native_id',x.value->'raw'->>'_id')=p_native
   then ingestion.redact_acnc_record_copy(x.value,p_field)
  else x.value end order by x.ordinality),'[]'::jsonb)
 from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) with ordinality x(value,ordinality)
$$;
revoke all on function ingestion.redact_acnc_record_array(jsonb,text,text)
 from public,anon,authenticated,service_role,ingestion_worker;

create function ingestion.redact_acnc_envelope(p_envelope jsonb,p_native text,p_field text)
returns jsonb language plpgsql immutable set search_path='' as $$
declare result jsonb; events jsonb;
begin
 result := jsonb_set(p_envelope,'{records}',ingestion.redact_acnc_record_array(p_envelope->'records',p_native,p_field),true);
 result := jsonb_set(result,'{quarantine}',ingestion.redact_acnc_record_array(result->'quarantine',p_native,p_field),true);
 events := coalesce(result->'retained_evidence_redactions','[]'::jsonb) ||
  jsonb_build_array(jsonb_build_object('native_id',p_native,'field',p_field));
 return jsonb_set(result,'{retained_evidence_redactions}',events,true);
end $$;
revoke all on function ingestion.redact_acnc_envelope(jsonb,text,text)
 from public,anon,authenticated,service_role,ingestion_worker;

create function ingestion.redact_snapshot_fields(p_items jsonb,p_field text)
returns jsonb language sql immutable set search_path='' as $$
 select coalesce(jsonb_agg(case
  when p_field='*' or x.value->>'field'=p_field then
   (x.value - 'source_value' - 'current_value' - 'input_value' - 'source_values') || jsonb_build_object('retained_evidence_redacted',true)
  else x.value end order by x.ordinality),'[]'::jsonb)
 from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) with ordinality x(value,ordinality)
$$;
revoke all on function ingestion.redact_snapshot_fields(jsonb,text)
 from public,anon,authenticated,service_role,ingestion_worker;

create function ingestion.retained_snapshot_needs_redaction(p_items jsonb,p_field text)
returns boolean language sql immutable set search_path='' as $$
 select exists(select 1 from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) x
  where (p_field='*' or x->>'field'=p_field)
   and (x ? 'source_value' or x ? 'current_value' or x ? 'input_value' or x ? 'source_values'))
$$;
revoke all on function ingestion.retained_snapshot_needs_redaction(jsonb,text)
 from public,anon,authenticated,service_role,ingestion_worker;

create function ingestion.redact_suppressed_retained_evidence(p_record bigint,p_field text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sr ingestion.source_records; s ingestion.suppressions;
 version_count integer:=0; assertion_count integer:=0; run_count integer:=0; checkpoint_count integer:=0;
 approval_count integer:=0; publication_count integer:=0;
begin
 if p_field is null or (p_field<>'*' and length(trim(p_field))=0) then
  raise exception 'Invalid redaction field' using errcode='22023';
 end if;
 select * into sr from ingestion.source_records where id=p_record for share;
 if not found then raise exception 'Source record not found' using errcode='P0002'; end if;
 select * into s from ingestion.suppressions where record_id=p_record and field=p_field;
 if not found then return jsonb_build_object('redacted',false,'reason','suppression not found'); end if;

 lock table ingestion.source_record_versions,ingestion.field_assertions,ingestion.ingestion_runs,
  ingestion.acquisition_jobs,ingestion.change_sets,ingestion.publications in share row exclusive mode;

 update ingestion.source_record_versions
 set payload=ingestion.redact_acnc_record_copy(payload,p_field)
 where record_id=p_record and ingestion.acnc_record_copy_needs_redaction(payload,p_field);
 get diagnostics version_count = row_count;

 delete from ingestion.field_assertions f using ingestion.source_record_versions v
 where f.version_id=v.id and v.record_id=p_record and (p_field='*' or f.field=p_field);
 get diagnostics assertion_count = row_count;

 update ingestion.ingestion_runs
 set envelope=ingestion.redact_acnc_envelope(envelope,sr.native_id,p_field),
  envelope_sha256=encode(sha256(convert_to(ingestion.redact_acnc_envelope(envelope,sr.native_id,p_field)::text,'UTF8')),'hex')
 where source_id=sr.source_id and resource_id=sr.resource_id and (
  exists(select 1 from jsonb_array_elements(coalesce(envelope->'records','[]'::jsonb)) x
   where coalesce(x->>'native_id',x->'raw'->>'_id')=sr.native_id
    and ingestion.acnc_record_copy_needs_redaction(x,p_field))
  or exists(select 1 from jsonb_array_elements(coalesce(envelope->'quarantine','[]'::jsonb)) x
   where coalesce(x->>'native_id',x->'raw'->>'_id')=sr.native_id
    and ingestion.acnc_record_copy_needs_redaction(x,p_field)));
 get diagnostics run_count = row_count;

 update ingestion.acquisition_jobs
 set checkpoint=ingestion.redact_acnc_envelope(checkpoint,sr.native_id,p_field),raw_removed_at=coalesce(raw_removed_at,now())
 where source_id=sr.source_id and resource_id=sr.resource_id and checkpoint is not null and (
  exists(select 1 from jsonb_array_elements(coalesce(checkpoint->'records','[]'::jsonb)) x
   where coalesce(x->>'native_id',x->'raw'->>'_id')=sr.native_id
    and ingestion.acnc_record_copy_needs_redaction(x,p_field))
  or exists(select 1 from jsonb_array_elements(coalesce(checkpoint->'quarantine','[]'::jsonb)) x
   where coalesce(x->>'native_id',x->'raw'->>'_id')=sr.native_id
    and ingestion.acnc_record_copy_needs_redaction(x,p_field)));
 get diagnostics checkpoint_count = row_count;

 update ingestion.change_sets c
 set fields=ingestion.redact_snapshot_fields(fields,p_field)
 from ingestion.source_record_versions v
 where c.version_id=v.id and v.record_id=p_record
  and ingestion.retained_snapshot_needs_redaction(c.fields,p_field);
 get diagnostics approval_count = row_count;

 update ingestion.publications p
 set changes=ingestion.redact_snapshot_fields(changes,p_field)
 from ingestion.change_sets c join ingestion.source_record_versions v on v.id=c.version_id
 where p.change_set_id=c.id and v.record_id=p_record
  and ingestion.retained_snapshot_needs_redaction(p.changes,p_field);
 get diagnostics publication_count = row_count;

 if version_count+assertion_count+run_count+checkpoint_count+approval_count+publication_count>0 then
  insert into ingestion.retained_evidence_redaction_events(source_id,resource_id,native_id,record_id,field,
   organisation_id,reason,suppressed_by,version_count,assertion_count,run_count,checkpoint_count,
   approval_count,publication_count)
  values(sr.source_id,sr.resource_id,sr.native_id,p_record,p_field,s.organisation_id,s.reason,s.suppressed_by,
   version_count,assertion_count,run_count,checkpoint_count,approval_count,publication_count);
 end if;
 return jsonb_build_object('redacted',true,'versions',version_count,'assertions',assertion_count,
  'runs',run_count,'checkpoints',checkpoint_count,'approvals',approval_count,'publications',publication_count);
end $$;
revoke all on function ingestion.redact_suppressed_retained_evidence(bigint,text)
 from public,anon,authenticated,service_role,ingestion_worker;

create or replace function community_orgs.suppress_ingestion_content(p_run text,p_version text,p_field text,p_reason text,p_expected jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare rec bigint; org uuid; snapshot jsonb; m ingestion.field_mappings; target_record bigint;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 select * into m from ingestion.field_mappings where field=p_field;
 if p_field is null or (p_field<>'*' and m.field is null) or p_reason is null or length(trim(p_reason)) not between 1 and 2000 then
  raise exception 'Invalid suppression' using errcode='22023'; end if;
 lock table community_orgs.organisations,community_orgs.legal_details,community_orgs.contact_info,community_orgs.acnc_register_details in share row exclusive mode;
 select sv.record_id into rec from ingestion.run_records rr join ingestion.source_record_versions sv on sv.id=rr.version_id
 where rr.run_id=p_run::bigint and rr.version_id=p_version::bigint;
 if not found then raise exception 'Record not in run' using errcode='P0002'; end if;
 select organisation_id into org from ingestion.source_links where record_id=rec;
 if p_expected->>'organisation_id' is distinct from org::text then raise exception 'Target changed; reload' using errcode='40001'; end if;
 if p_field<>'*' and org is not null then
  snapshot := community_orgs.ingestion_field_preview(p_run,p_version,org);
  if not exists(select 1 from jsonb_array_elements(snapshot->'fields') f where f=p_expected->'field' and f->>'field'=p_field and (f->>'target_rows')::int<=1) then
   raise exception 'Target field changed or ambiguous; reload' using errcode='40001'; end if;
 end if;
 insert into ingestion.suppressions(record_id,field,organisation_id,reason,suppressed_by)
 values(rec,p_field,org,trim(p_reason),auth.uid()) on conflict do nothing;
 perform ingestion.redact_suppressed_retained_evidence(rec,p_field);
 if org is not null then
  if p_field in ('*','entity_name') then
   update community_orgs.organisations set is_public=false where org_id=org;
   update community_orgs.acnc_register_details set is_public=false where org_id=org;
  elsif m.table_name='acnc_register_details' then
   for target_record in select source_record_id from community_orgs.acnc_register_details where org_id=org loop
    perform ingestion.write_field(org,target_record,p_field,null);
   end loop;
  else
   perform ingestion.write_field(org,rec,p_field,null);
  end if;
 end if;
end $$;
revoke all on function community_orgs.suppress_ingestion_content(text,text,text,text,jsonb) from public,anon,service_role;
grant execute on function community_orgs.suppress_ingestion_content(text,text,text,text,jsonb) to authenticated;

alter function ingestion.stage_acnc(jsonb) rename to stage_acnc_before_suppression_redaction;
revoke all on function ingestion.stage_acnc_before_suppression_redaction(jsonb)
 from public,anon,authenticated,service_role,ingestion_worker;
create function ingestion.stage_acnc(p_envelope jsonb) returns bigint
language plpgsql security definer set search_path='' as $$
declare run bigint; rec record;
begin
 run := ingestion.stage_acnc_before_suppression_redaction(p_envelope);
 for rec in
  select distinct sr.id,s.field from ingestion.run_records rr
  join ingestion.source_record_versions v on v.id=rr.version_id
  join ingestion.source_records sr on sr.id=v.record_id
  join ingestion.suppressions s on s.record_id=sr.id
  where rr.run_id=run
 loop
  perform ingestion.redact_suppressed_retained_evidence(rec.id,rec.field);
 end loop;
 return run;
end $$;
revoke all on function ingestion.stage_acnc(jsonb) from public,anon,authenticated,service_role;
grant execute on function ingestion.stage_acnc(jsonb) to ingestion_worker;

alter function ingestion.checkpoint_acquisition(uuid,uuid,jsonb) rename to checkpoint_acquisition_before_suppression_redaction;
revoke all on function ingestion.checkpoint_acquisition_before_suppression_redaction(uuid,uuid,jsonb)
 from public,anon,authenticated,service_role,ingestion_worker;
create function ingestion.checkpoint_acquisition(p_job uuid,p_token uuid,p_envelope jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare rec record;
begin
 perform ingestion.checkpoint_acquisition_before_suppression_redaction(p_job,p_token,p_envelope);
 for rec in
  select distinct sr.id,s.field from ingestion.source_records sr
  join ingestion.suppressions s on s.record_id=sr.id
  where sr.source_id=p_envelope->>'source_id' and sr.resource_id=p_envelope->>'resource_id'
   and exists(select 1 from jsonb_array_elements(coalesce(p_envelope->'records','[]'::jsonb)) x
    where coalesce(x->>'native_id',x->'raw'->>'_id')=sr.native_id)
 loop
  perform ingestion.redact_suppressed_retained_evidence(rec.id,rec.field);
 end loop;
end $$;
revoke all on function ingestion.checkpoint_acquisition(uuid,uuid,jsonb)
 from public,anon,authenticated,service_role,ingestion_worker;
grant execute on function ingestion.checkpoint_acquisition(uuid,uuid,jsonb) to ingestion_worker;

comment on table ingestion.retained_evidence_redaction_events is
 'Private audit of targeted retained-evidence redaction caused by ingestion suppression/withdrawal. Suppression reasons remain private and attributable.';
