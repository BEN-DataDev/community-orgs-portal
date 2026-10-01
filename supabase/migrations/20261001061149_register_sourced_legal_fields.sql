-- Legal details supplied by a public register (ABR, ACNC, NSW Incorporated
-- Associations) are read-only to portal users. A column is locked for an
-- organisation only when it holds the register record that supplied it, so
-- organisations outside the registers, and columns no register supplied, stay
-- editable. Corrections go through the reviewed ingestion and steward workflows,
-- which run as security definer functions and are not restricted here.
--
-- This supersedes P10 "manual field ownership" for these columns: a portal edit can
-- no longer replace a register value.
begin;

create index full_seed_items_abr_abn_idx
  on ingestion.full_seed_items(abn)
  where source_refs ? 'abr_version_id';

create function community_orgs.register_sourced_legal_fields(p_organisation uuid)
returns text[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(distinct field order by field), '{}')
  from (
    select unnest(array['abn', 'abn_status', 'abn_activated', 'abn_last_updated', 'entity_type']) field
    where exists (
      select 1 from ingestion.identifier_keys k
      join ingestion.full_seed_items i on i.abn = k.normalized_value and i.source_refs ? 'abr_version_id'
      where k.holder = p_organisation and k.scheme = 'abn' and k.jurisdiction = 'AU' and k.state = 'verified')
    union all
    select unnest(array['abn', 'acnc_registered_date'])
    where exists (
      select 1 from ingestion.source_links l
      join ingestion.source_records r on r.id = l.record_id
      where l.organisation_id = p_organisation and r.source_id = 'acnc-register')
    union all
    select unnest(array['incorporation_number', 'incorporation_status',
      'incorporation_registration_date', 'entity_type'])
    where exists (
      select 1 from ingestion.identifier_keys k
      join ingestion.full_seed_items i on i.incorporation_number = k.normalized_value
        and i.source_refs ? 'nsw_version_id'
      where k.holder = p_organisation and k.scheme = 'incorporated_association'
        and k.jurisdiction = 'AU-NSW' and k.state = 'verified')
  ) sourced
$$;

-- Security invoker on purpose: current_user is then the API role for a direct
-- client write, and the function owner inside reviewed security definer workflows.
create function community_orgs.guard_register_sourced_legal_fields()
returns trigger language plpgsql set search_path = '' as $$
declare
  old_row jsonb := to_jsonb(OLD);
  new_row jsonb := case when TG_OP = 'UPDATE' then to_jsonb(NEW) end;
  field text;
begin
  if current_user not in ('authenticated', 'anon') then
    return coalesce(NEW, OLD);
  end if;
  foreach field in array community_orgs.register_sourced_legal_fields(OLD.org_id) loop
    if (TG_OP = 'DELETE' and jsonb_typeof(old_row->field) <> 'null')
       or (TG_OP = 'UPDATE' and (new_row->field is distinct from old_row->field
         or NEW.org_id is distinct from OLD.org_id)) then
      raise exception '% comes from a public register and cannot be edited', field
        using errcode = '42501';
    end if;
  end loop;
  return coalesce(NEW, OLD);
end
$$;

create trigger guard_register_sourced_legal_fields
  before update or delete on community_orgs.legal_details
  for each row execute function community_orgs.guard_register_sourced_legal_fields();

revoke all on function community_orgs.register_sourced_legal_fields(uuid)
  from public, anon, service_role, ingestion_worker;
grant execute on function community_orgs.register_sourced_legal_fields(uuid) to authenticated;
revoke all on function community_orgs.guard_register_sourced_legal_fields() from public;

comment on function community_orgs.register_sourced_legal_fields(uuid) is
  'legal_details columns supplied by a public register record this organisation holds; read-only to portal users.';

commit;
