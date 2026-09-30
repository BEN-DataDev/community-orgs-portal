-- The seed correction is applied. Remove its management-only bypass branches from
-- the identity and field-protection audit triggers, and stop retaining raw
-- acquisition checkpoints once the run is staged (the run envelope keeps them).
begin;

do $$ begin
  if exists(select 1 from ingestion.seed_publication_corrections where status <> 'applied') then
    raise exception 'A seed correction is still in progress';
  end if;
end $$;

drop function ingestion.apply_seed_publication_correction_managed_batch(uuid,integer);

create or replace function ingestion.identity_audit() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update ingestion.identity_clock set revision = revision + 1 where singleton;
  insert into ingestion.identity_events(action, subject, before_value, after_value, actor)
  values (
    TG_OP,
    TG_TABLE_NAME,
    case when TG_OP <> 'INSERT' then to_jsonb(old) end,
    case when TG_OP <> 'DELETE' then to_jsonb(new) end,
    auth.uid()
  );
  return coalesce(new, old);
end
$$;

create or replace function ingestion.dispute_edited_identity() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='UPDATE' and (new.abn,new.acn,new.incorporation_number,new.org_id) is not distinct from
  (old.abn,old.acn,old.incorporation_number,old.org_id) then return new; end if;
 -- Writing the same accepted value (including import projection and display
 -- spacing) does not dispute registry evidence. Clears, changed values, moves
 -- and deletion of identifier-bearing rows do.
 update ingestion.identifier_keys k set state='disputed',revision=revision+1
 where k.state='verified' and (
  (TG_OP<>'INSERT' and k.holder=old.org_id and
   (TG_OP='DELETE' or old.org_id is distinct from new.org_id) and
   case k.scheme when 'abn' then old.abn is not null else old.incorporation_number is not null end)
  or (TG_OP<>'DELETE' and k.holder=new.org_id and
   case k.scheme when 'abn' then
    (case when TG_OP='INSERT' then new.abn is not null else new.abn is distinct from old.abn or new.org_id is distinct from old.org_id end)
    and ingestion.normalize_identifier('abn','AU',new.abn) is distinct from k.normalized_value
   else
    (case when TG_OP='INSERT' then new.incorporation_number is not null else new.incorporation_number is distinct from old.incorporation_number or new.org_id is distinct from old.org_id end)
    and btrim(new.incorporation_number) is distinct from k.normalized_value
   end));
 return coalesce(new,old);
end $$;

create or replace function ingestion.protect_portal_fields() returns trigger
language plpgsql security definer set search_path='' as $$
declare
 old_row jsonb; new_row jsonb; org uuid; scope bigint:=0;
 m ingestion.field_mappings; before_value jsonb; after_value jsonb;
begin
 if TG_OP<>'INSERT' then old_row:=to_jsonb(OLD); end if;
 if TG_OP<>'DELETE' then new_row:=to_jsonb(NEW); end if;
 if TG_OP='UPDATE' and (old_row->'org_id' is distinct from new_row->'org_id'
  or old_row->'source_record_id' is distinct from new_row->'source_record_id') then
  raise exception 'Identity reassignment requires a reviewed migration' using errcode='22023'; end if;
 org:=coalesce((new_row->>'org_id')::uuid,(old_row->>'org_id')::uuid);
 if org is null or not exists(select 1 from community_orgs.organisations where org_id=org) then return null; end if;
 if TG_TABLE_NAME='acnc_register_details' then
  scope:=coalesce((new_row->>'source_record_id')::bigint,(old_row->>'source_record_id')::bigint);
 end if;
 for m in select * from ingestion.field_mappings where table_name=TG_TABLE_NAME loop
  before_value:=old_row->m.column_name; after_value:=new_row->m.column_name;
  if m.path is not null then before_value:=before_value->m.path; after_value:=after_value->m.path; end if;
  if TG_OP='DELETE' or nullif(before_value,'null'::jsonb) is distinct from nullif(after_value,'null'::jsonb) then
   insert into ingestion.field_state(org_id,table_name,field,record_id,changed_by)
   values(org,TG_TABLE_NAME,m.field,scope,auth.uid())
   on conflict(org_id,table_name,field,record_id) do update set
    revision=ingestion.field_state.revision+1,protected=true,changed_by=auth.uid(),changed_at=clock_timestamp();
  end if;
 end loop;
 return null;
end $$;

-- Staging copies the checkpoint into ingestion_runs.envelope; keeping a second raw
-- copy on the finished job only widens retention and redaction scope.
create or replace function ingestion.finish_acquisition(p_job uuid, p_token uuid)
returns bigint language plpgsql security definer set search_path = '' as $$
declare j ingestion.acquisition_jobs; r bigint;
begin
  j := ingestion.lock_acquisition(p_job, p_token);
  if j.checkpoint is null then raise exception 'Acquisition checkpoint required'; end if;
  r := ingestion.stage_acnc(j.checkpoint);
  insert into ingestion.run_scope_attributions(
    run_id, scope_revision_id, alignment, reason, attributed_by
  ) values (
    r, (j.config->>'portal_scope_revision_id')::bigint,
    j.config->>'scope_alignment', 'Recorded atomically from the fenced acquisition job', j.requested_by
  ) on conflict (run_id) do nothing;
  update ingestion.acquisition_jobs
  set status = j.checkpoint->>'completion', run_id = r, finished_at = now(),
      lease_token = null, lease_until = null, checkpoint = null,
      message = case when j.checkpoint->>'completion' = 'complete' then 'Ready for review.'
        else 'Incomplete acquisition; inspect the retained import errors. Publication is blocked.' end
  where id = p_job;
  return r;
end
$$;

-- Clear checkpoints already staged into a run.
update ingestion.acquisition_jobs set checkpoint = null
where checkpoint is not null and run_id is not null;

-- A staged job's evidence now lives on its run.
create or replace function community_orgs.acquisition_dashboard()
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if community_orgs.is_ingestion_operator() is distinct from true then
    raise exception 'Operator required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'portal_scope_revision_id', (select current_scope_revision_id::text from portal.configuration where singleton),
    'sources', coalesce((select jsonb_agg(jsonb_build_object(
      'resource_id', s.resource_id, 'enabled', s.enabled,
      'title', coalesce(s.metadata->>'public_title', s.source_id),
      'postcodes', c.postcodes, 'licence_title', coalesce(c.licence_title, s.metadata->>'public_licence', ''),
      'interval_hours', c.interval_hours, 'next_due_at', c.next_due_at,
      'revision', coalesce(c.revision, 0)::text,
      'scope_revision_id', c.scope_revision_id::text, 'scope_alignment', c.scope_alignment,
      'scope_exception_reason', c.scope_exception_reason
    ) order by s.resource_id)
    from ingestion.sources s left join ingestion.acquisition_configs c using(source_id, resource_id)
    where s.source_id = 'acnc-register' and coalesce(s.metadata->>'synthetic', 'false') = 'false'), '[]'::jsonb),
    'jobs', coalesce((select jsonb_agg(to_jsonb(j)) from (
      select id::text, resource_id, status, origin, attempts, created_at, available_at, lease_until,
        finished_at, run_id::text, message, checkpoint is not null or run_id is not null as acquired
      from ingestion.acquisition_jobs order by created_at desc limit 50
    ) j), '[]'::jsonb)
  );
end
$$;

commit;
