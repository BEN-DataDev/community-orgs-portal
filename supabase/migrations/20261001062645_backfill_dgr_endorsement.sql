-- The full seed never copied DGR status from the ABR. Backfill dgr_endorsement for
-- every organisation holding an ABR record: true when the record lists a DGR
-- endorsement, either for the entity itself or for a fund it operates (the ATO
-- endorses the entity to operate the fund); false when it lists none, since the ABR
-- is the register of DGR endorsement. The retained extract lists only current
-- endorsements: every entity-level entry is ACT, including on cancelled ABNs.
-- dgr_endorsement then becomes an ABR-supplied, read-only column.
begin;

with abr as (
  select item.abn,
    (select a->'value' from jsonb_array_elements(cv.payload->'assertions') a
     where a->>'field' = 'abr_dgr') dgr
  from ingestion.full_seed_items item
  join ingestion.registry_seed_candidate_versions cv on cv.id = (item.source_refs->>'abr_version_id')::bigint
  where item.source_refs ? 'abr_version_id'
)
update community_orgs.legal_details ld set dgr_endorsement = exists (
    select 1 from jsonb_array_elements(case when jsonb_typeof(abr.dgr) = 'array' then abr.dgr else '[]' end) e
    where e->>'status' = 'ACT' or (e->>'type' = 'DGR' and e->>'name' is not null))
from abr
join ingestion.identifier_keys k on k.scheme = 'abn' and k.jurisdiction = 'AU'
  and k.normalized_value = abr.abn and k.state = 'verified'
where ld.org_id = k.holder
  and ld.abn = abr.abn
  and ld.dgr_endorsement is null;

create or replace function community_orgs.register_sourced_legal_fields(p_organisation uuid)
returns text[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(distinct field order by field), '{}')
  from (
    select unnest(array['abn', 'abn_status', 'abn_activated', 'abn_last_updated',
      'dgr_endorsement', 'entity_type']) field
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

commit;
