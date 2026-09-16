-- Field protection is deliberately conservative: existing values and subsequent
-- portal writes are protected. No publication path or client-controlled bypass.
create table ingestion.field_state (
 org_id uuid not null references community_orgs.organisations(org_id) on delete cascade,
 table_name text not null,
 field text not null,
 revision bigint not null default 1,
 protected boolean not null default true,
 changed_by uuid,
 changed_at timestamptz not null default now(),
 primary key (org_id, table_name, field)
);
alter table ingestion.field_state enable row level security;
revoke all on ingestion.field_state from public, anon, authenticated, service_role;

create function ingestion.protect_portal_fields() returns trigger
language plpgsql security definer set search_path = '' as $$
declare old_row jsonb; new_row jsonb; org uuid; f text;
begin
 if TG_OP <> 'INSERT' then old_row := to_jsonb(old); end if;
 if TG_OP <> 'DELETE' then new_row := to_jsonb(new); end if;
 -- Moving child rows changes both organisations; disallow it for these fields
 -- rather than leaving an untracked removal. Existing forms do not move rows.
 if TG_OP='UPDATE' and old_row->>'org_id' is distinct from new_row->>'org_id' then
  raise exception 'Organisation reassignment requires a reviewed migration' using errcode='22023';
 end if;
 org := coalesce((new_row->>'org_id')::uuid,(old_row->>'org_id')::uuid);
 if org is null or not exists(select 1 from community_orgs.organisations where org_id=org) then
  return null; -- Parent deletion/cascade has no surviving field state.
 end if;
 foreach f in array TG_ARGV loop
  if (TG_OP='INSERT' and new_row->f is distinct from 'null'::jsonb)
    or (TG_OP='DELETE')
    or (TG_OP='UPDATE' and old_row->f is distinct from new_row->f) then
   insert into ingestion.field_state(org_id,table_name,field,changed_by)
   values(org,TG_TABLE_NAME,f,auth.uid())
   on conflict (org_id,table_name,field) do update
    set revision=ingestion.field_state.revision+1, protected=true,
        changed_by=auth.uid(), changed_at=now();
  end if;
 end loop;
 return null;
end $$;
revoke all on function ingestion.protect_portal_fields() from public, anon, authenticated, service_role;
create trigger ingestion_protect_organisation after insert or update on community_orgs.organisations
 for each row execute function ingestion.protect_portal_fields('entity_name');
create trigger ingestion_protect_legal after insert or update or delete on community_orgs.legal_details
 for each row execute function ingestion.protect_portal_fields('abn');
create trigger ingestion_protect_contact after insert or update or delete on community_orgs.contact_info
 for each row execute function ingestion.protect_portal_fields('website');

-- Existing data has no trustworthy import provenance; preserve it by default.
insert into ingestion.field_state(org_id,table_name,field)
 select org_id,'organisations','entity_name' from community_orgs.organisations where entity_name is not null
 union select l.org_id,'legal_details','abn' from community_orgs.legal_details l
 join community_orgs.organisations o on o.org_id=l.org_id where l.abn is not null
 union select c.org_id,'contact_info','website' from community_orgs.contact_info c
 join community_orgs.organisations o on o.org_id=c.org_id where c.website is not null;

create function community_orgs.ingestion_field_preview(p_run text, p_version text, p_organisation uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a record; t text; current_value jsonb; n bigint; state ingestion.field_state;
 result jsonb := '[]'; status text; supported boolean; target_name text;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then
  raise exception 'Ingestion operator access required' using errcode='42501';
 end if;
 if not exists(select 1 from ingestion.run_records where run_id=p_run::bigint and version_id=p_version::bigint) then
  raise exception 'Record not in selected run' using errcode='P0002';
 end if;
 if p_organisation is not null then
  select entity_name into target_name from community_orgs.organisations where org_id=p_organisation;
  if not found then raise exception 'Organisation not found' using errcode='P0002'; end if;
 end if;
 -- Include missing mapped assertions explicitly: absence is never a deletion.
 for a in
  select f.field, f.value, true as present from ingestion.field_assertions f where version_id=p_version::bigint
  union all
  select f, null::jsonb, false from unnest(array['entity_name','abn','website']) f
   where not exists(select 1 from ingestion.field_assertions x where x.version_id=p_version::bigint and x.field=f)
  order by 1
 loop
  t := case a.field when 'entity_name' then 'organisations' when 'abn' then 'legal_details' when 'website' then 'contact_info' end;
  current_value := null; n := 0; state := null;
  supported := t is not null;
  if supported and p_organisation is not null then
   -- Both identifiers are from the closed mapping above, never source input.
   execute format('select count(*), (jsonb_agg(to_jsonb(x.%I)))->0 from community_orgs.%I x where org_id=$1',a.field,t)
    into n,current_value using p_organisation;
   select * into state from ingestion.field_state where org_id=p_organisation and table_name=t and field=a.field;
  end if;
  status := case
   when not supported then 'unmapped'
   when not a.present or a.value='null'::jsonb then 'missing'
   when jsonb_typeof(a.value)<>'string' or length(trim(a.value #>> '{}'))=0 then 'invalid'
   when n>1 then 'ambiguous'
   when current_value is not distinct from a.value then 'unchanged'
   when coalesce(state.protected,false) then 'conflict'
   when current_value is null or current_value='null'::jsonb then 'new'
   else 'changed' end;
  result := result || jsonb_build_array(jsonb_build_object(
   'field',a.field,'table',t,'source_value',a.value,'current_value',case when n>1 then null else current_value end,
   'status',status,'protected',coalesce(state.protected,false),'revision',coalesce(state.revision,0)::text,
   'target_rows',n,'changed_at',state.changed_at));
 end loop;
 return jsonb_build_object('organisation_id',p_organisation,'organisation_name',target_name,'fields',result);
end $$;
revoke all on function community_orgs.ingestion_field_preview(text,text,uuid) from public, anon, service_role;
grant execute on function community_orgs.ingestion_field_preview(text,text,uuid) to authenticated;
