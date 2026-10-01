-- prepare_full_seed_union only accepted ISO registration dates, and its doubled
-- backslash ('^\\d{4}-...') matched nothing anyway, so every NSW association was
-- seeded without one. Backfill from the retained register assertion, which displays
-- d/m/yyyy. The seed item is corrected too, so a split merge review recreates the
-- association with its date. Only rows still holding the association's number and an
-- empty date are touched; neither identity nor field-protection triggers react to
-- this column.
begin;

with parsed as (
  select item.publication_id, item.canonical_key, item.incorporation_number, reg.registered
  from ingestion.full_seed_items item
  join ingestion.registry_seed_candidate_versions cv on cv.id = (item.source_refs->>'nsw_version_id')::bigint
  cross join lateral (
    select regexp_match(a->>'value', '^(\d{1,2})/(\d{1,2})/(\d{4})$') p
    from jsonb_array_elements(cv.payload->'assertions') a
    where a->>'field' = 'nsw_date_registered' limit 1
  ) dm
  cross join lateral (select case
    when dm.p is null or dm.p[3]::int < 1 or dm.p[2]::int not between 1 and 12 then null
    when dm.p[1]::int between 1 and extract(day from make_date(dm.p[3]::int, dm.p[2]::int, 1) + interval '1 month -1 day')
      then make_date(dm.p[3]::int, dm.p[2]::int, dm.p[1]::int) end registered) reg
  where item.source_refs ? 'nsw_version_id'
    and item.incorporation_registration_date is null
    and reg.registered is not null
), items as (
  update ingestion.full_seed_items item set incorporation_registration_date = p.registered
  from parsed p
  where item.publication_id = p.publication_id and item.canonical_key = p.canonical_key
)
update community_orgs.legal_details ld set incorporation_registration_date = p.registered
from parsed p
join ingestion.identifier_keys k on k.scheme = 'incorporated_association' and k.jurisdiction = 'AU-NSW'
  and k.normalized_value = p.incorporation_number and k.state = 'verified'
where ld.org_id = k.holder
  and ld.incorporation_number = p.incorporation_number
  and ld.incorporation_registration_date is null;

commit;
