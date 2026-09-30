-- P29: guarded rollback of committed import-owned field changes.
-- Clean fields are restored only when the target revision and value still match
-- the publication snapshot. Later human edits are queued as private conflicts.
create table ingestion.rollbacks (
 id uuid primary key default gen_random_uuid(),
 change_set_id uuid not null references ingestion.publications(change_set_id),
 organisation_id uuid not null references community_orgs.organisations,
 reason text not null check(length(trim(reason)) between 1 and 2000),
 status text not null check(status in ('complete','partial_conflict','conflict_only')),
 requested_by uuid not null references auth.users,
 requested_at timestamptz not null default now(),
 result jsonb not null
);

create table ingestion.rollback_events (
 id bigint generated always as identity primary key,
 rollback_id uuid not null references ingestion.rollbacks(id) on delete cascade,
 change_set_id uuid not null references ingestion.publications(change_set_id),
 organisation_id uuid not null references community_orgs.organisations,
 record_id bigint not null references ingestion.source_records,
 target_record_id bigint not null,
 field text not null,
 table_name text,
 action text not null check(action in ('reversed','conflict')),
 reason text not null,
 previous_value jsonb,
 imported_value jsonb,
 current_value jsonb,
 expected_revision bigint,
 current_revision bigint,
 created_at timestamptz not null default now()
);

alter table ingestion.rollbacks enable row level security;
alter table ingestion.rollback_events enable row level security;
revoke all on ingestion.rollbacks,ingestion.rollback_events
 from public,anon,authenticated,service_role,ingestion_worker;
revoke all on sequence ingestion.rollback_events_id_seq
 from public,anon,authenticated,service_role,ingestion_worker;

create function ingestion.current_field_value(p_org uuid,p_record bigint,p_field text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m ingestion.field_mappings; expr text; predicate text; result jsonb;
begin
 select * into m from ingestion.field_mappings where field=p_field;
 if not found then raise exception 'Unsupported field' using errcode='22023'; end if;
 expr:=format('to_jsonb(x.%I)',m.column_name);
 if m.path is not null then expr:=format('(%s)->%L',expr,m.path); end if;
 predicate:=case when m.table_name='acnc_register_details' then ' and source_record_id=$2' else '' end;
 execute format('select (jsonb_agg(%s))->0 from community_orgs.%I x where org_id=$1%s',
  expr,m.table_name,predicate) into result using p_org,p_record;
 return result;
end $$;
revoke all on function ingestion.current_field_value(uuid,bigint,text)
 from public,anon,authenticated,service_role,ingestion_worker;

create function community_orgs.rollback_ingestion_publication(p_change_set uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 p ingestion.publications; c ingestion.change_sets; f jsonb; m ingestion.field_mappings;
 rec bigint; field_record bigint; current_value jsonb; state_revision bigint;
 expected_revision bigint; rollback_id uuid; reversed_count integer:=0;
 conflict_count integer:=0; created_target boolean; created_guard_failed boolean:=false;
 rollback_status text; rollback_result jsonb;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then
  raise exception 'Operator required' using errcode='42501';
 end if;
 if p_reason is null or length(trim(p_reason)) not between 1 and 2000 then
  raise exception 'Rollback reason required' using errcode='22023';
 end if;
 lock table community_orgs.organisations,community_orgs.legal_details,
  community_orgs.contact_info,community_orgs.acnc_register_details in share row exclusive mode;
 lock table ingestion.field_mappings,ingestion.source_record_versions,ingestion.field_assertions,
  ingestion.run_records,ingestion.rollbacks,ingestion.rollback_events in share row exclusive mode;
 select * into p from ingestion.publications where change_set_id=p_change_set for update;
 if not found then raise exception 'Publication not found' using errcode='P0002'; end if;
 select * into c from ingestion.change_sets where id=p.change_set_id for share;
 select record_id into rec from ingestion.source_record_versions where id=c.version_id;
 select exists(select 1 from ingestion.creation_targets where change_set_id=p.change_set_id)
  into created_target;

 insert into ingestion.rollbacks(change_set_id,organisation_id,reason,status,requested_by,result)
 values(p.change_set_id,p.organisation_id,trim(p_reason),'conflict_only',auth.uid(),'{}')
 returning id into rollback_id;

 for f in select value from jsonb_array_elements(p.changes) loop
  select * into m from ingestion.field_mappings where field=f->>'field';
  field_record:=coalesce(nullif(f->>'record_id','')::bigint,case when m.table_name='acnc_register_details' then rec else 0 end);
  current_value:=null;
  state_revision:=null;
  expected_revision:=case when f ? 'revision' then (f->>'revision')::bigint+1 else null end;
  if m.field is null or not (f ? 'source_value') or not (f ? 'current_value') or expected_revision is null then
   conflict_count:=conflict_count+1;
   insert into ingestion.rollback_events(rollback_id,change_set_id,organisation_id,record_id,target_record_id,field,table_name,
   action,reason,previous_value,imported_value,current_value,expected_revision,current_revision)
   values(rollback_id,p.change_set_id,p.organisation_id,rec,field_record,coalesce(f->>'field',''),m.table_name,'conflict',
    'Publication snapshot is unavailable or no longer rollback-capable',
    f->'current_value',f->'source_value',null,expected_revision,null);
   if created_target then created_guard_failed:=true; end if;
   continue;
  end if;
  current_value:=ingestion.current_field_value(p.organisation_id,field_record,m.field);
  select revision into state_revision from ingestion.field_state
   where org_id=p.organisation_id and table_name=m.table_name and field=m.field and record_id=field_record;
  if state_revision is distinct from expected_revision or current_value is distinct from f->'source_value' then
   conflict_count:=conflict_count+1;
   insert into ingestion.rollback_events(rollback_id,change_set_id,organisation_id,record_id,target_record_id,field,table_name,
   action,reason,previous_value,imported_value,current_value,expected_revision,current_revision)
   values(rollback_id,p.change_set_id,p.organisation_id,rec,field_record,m.field,m.table_name,'conflict',
    'Target changed after import publication; manual review required',
    f->'current_value',f->'source_value',current_value,expected_revision,state_revision);
   if created_target then created_guard_failed:=true; end if;
   continue;
  end if;
  if created_target and m.field='entity_name' and nullif(f->'current_value','null'::jsonb) is null then
   reversed_count:=reversed_count+1;
   insert into ingestion.rollback_events(rollback_id,change_set_id,organisation_id,record_id,target_record_id,field,table_name,
   action,reason,previous_value,imported_value,current_value,expected_revision,current_revision)
   values(rollback_id,p.change_set_id,p.organisation_id,rec,field_record,m.field,m.table_name,'reversed',
    'Import-created target will be hidden after all field guards pass',
    f->'current_value',f->'source_value',current_value,expected_revision,state_revision);
  else
   perform ingestion.write_field(p.organisation_id,field_record,m.field,
    case when f->'current_value'='null'::jsonb then null else f->'current_value' end);
   reversed_count:=reversed_count+1;
   insert into ingestion.rollback_events(rollback_id,change_set_id,organisation_id,record_id,target_record_id,field,table_name,
   action,reason,previous_value,imported_value,current_value,expected_revision,current_revision)
   values(rollback_id,p.change_set_id,p.organisation_id,rec,field_record,m.field,m.table_name,'reversed',
    'Restored previous value because target revision still matched publication',
    f->'current_value',f->'source_value',current_value,expected_revision,state_revision);
  end if;
 end loop;

 if created_target and not created_guard_failed then
  update community_orgs.organisations set is_public=false where org_id=p.organisation_id;
  update community_orgs.acnc_register_details set is_public=false where org_id=p.organisation_id and source_record_id=rec;
 end if;

 rollback_status:=case when conflict_count=0 then 'complete'
  when reversed_count=0 then 'conflict_only' else 'partial_conflict' end;
 rollback_result:=jsonb_build_object('rollback_id',rollback_id,'change_set_id',p.change_set_id,
  'organisation_id',p.organisation_id,'status',rollback_status,'reversed',reversed_count,
  'conflicts',conflict_count,'created_target_hidden',created_target and not created_guard_failed);
 update ingestion.rollbacks set status=rollback_status,result=rollback_result where id=rollback_id;
 return rollback_result;
end $$;

create function community_orgs.ingestion_rollback_queue(p_change_set uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if community_orgs.is_ingestion_operator() is distinct from true then
  raise exception 'Operator required' using errcode='42501';
 end if;
 return (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]') from (
  select e.id,e.rollback_id,e.change_set_id,e.organisation_id,e.record_id,e.field,e.table_name,
   e.target_record_id,e.action,e.reason,e.previous_value,e.imported_value,e.current_value,e.expected_revision,
   e.current_revision,e.created_at,r.status,r.reason as rollback_reason
  from ingestion.rollback_events e join ingestion.rollbacks r on r.id=e.rollback_id
  where e.action='conflict' and (p_change_set is null or e.change_set_id=p_change_set)
  order by e.created_at desc,e.id desc limit 100
 ) x);
end $$;

revoke all on function community_orgs.rollback_ingestion_publication(uuid,text),
 community_orgs.ingestion_rollback_queue(uuid) from public,anon,service_role,ingestion_worker;
grant execute on function community_orgs.rollback_ingestion_publication(uuid,text),
 community_orgs.ingestion_rollback_queue(uuid) to authenticated;

comment on table ingestion.rollbacks is
 'Private operator ledger for guarded rollback attempts against committed import publications.';
comment on table ingestion.rollback_events is
 'Per-field rollback outcomes. Conflict rows are the review queue for fields changed after import.';
