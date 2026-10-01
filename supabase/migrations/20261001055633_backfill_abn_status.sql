-- The full seed copied only the ABN, leaving abn_status, abn_activated and
-- abn_last_updated empty for every organisation. Backfill them from the retained ABR
-- assertions: ACT is active and its status date is the activation date; CAN is
-- cancelled, and its status date is the cancellation, so no activation date is set.
-- Only empty columns on the verified ABN holder are filled. None of these columns is
-- a mapped source field, so field protection and identity triggers do not react.
begin;

with abr as (
  select item.abn, asserted.v->'abr_abn_status' status, asserted.v->>'abr_record_last_updated_date' updated
  from ingestion.full_seed_items item
  join ingestion.registry_seed_candidate_versions cv on cv.id = (item.source_refs->>'abr_version_id')::bigint
  cross join lateral (select jsonb_object_agg(a->>'field', a->'value') v
    from jsonb_array_elements(cv.payload->'assertions') a) asserted
  where item.source_refs ? 'abr_version_id'
    and asserted.v->'abr_abn_status'->>'status' in ('ACT', 'CAN')
)
update community_orgs.legal_details ld set
  abn_status = coalesce(ld.abn_status, abr.status->>'status' = 'ACT'),
  abn_activated = coalesce(ld.abn_activated, case
    when abr.status->>'status' = 'ACT' and abr.status->>'from' ~ '^\d{4}-\d{2}-\d{2}$'
      then (abr.status->>'from')::date end),
  abn_last_updated = coalesce(ld.abn_last_updated, case
    when abr.updated ~ '^\d{4}-\d{2}-\d{2}$' then abr.updated::date end)
from abr
join ingestion.identifier_keys k on k.scheme = 'abn' and k.jurisdiction = 'AU'
  and k.normalized_value = abr.abn and k.state = 'verified'
where ld.org_id = k.holder
  and ld.abn = abr.abn
  and (ld.abn_status is null or ld.abn_activated is null or ld.abn_last_updated is null);

commit;
