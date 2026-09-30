-- During the management-only correction, child field-state rows are deleted with
-- their newly imported parent. Avoid recreating those rows immediately before the
-- parent cascade; all ordinary writes retain the existing protection behaviour.
begin;

create or replace function ingestion.protect_portal_fields() returns trigger
language plpgsql security definer set search_path='' as $$
declare
 old_row jsonb; new_row jsonb; org uuid; scope bigint:=0;
 m ingestion.field_mappings; before_value jsonb; after_value jsonb;
 bulk_correction text;
begin
 bulk_correction:=current_setting('community_orgs.seed_correction_bulk',true);
 if session_user='postgres' and bulk_correction is not null
    and bulk_correction ~ '^[0-9a-f-]{36}$'
    and exists(select 1 from ingestion.seed_publication_corrections
      where correction_id=bulk_correction::uuid and status='applying') then
   return null;
 end if;
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

commit;
