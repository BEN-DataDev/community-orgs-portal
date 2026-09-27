-- Keep registry-seed queue reads bounded by extracting the redacted assertion
-- fields once at write time. The full provider payload remains private.
begin;

create table if not exists ingestion.registry_seed_candidate_facets (
  version_id bigint primary key references ingestion.registry_seed_candidate_versions(id) on delete restrict,
  candidate_id bigint not null references ingestion.registry_seed_candidates(id) on delete restrict,
  source_id text not null,
  resource_id text not null,
  native_id text not null,
  entity_name text,
  entity_type text,
  postcode text,
  has_dgr boolean not null
);

alter table ingestion.registry_seed_candidate_facets
  alter column source_id set not null,
  alter column resource_id set not null,
  alter column native_id set not null;

alter table ingestion.registry_seed_candidate_facets enable row level security;
revoke all on ingestion.registry_seed_candidate_facets
  from public, anon, authenticated, service_role, ingestion_worker;

create index if not exists registry_seed_candidate_facets_entity_type_idx
  on ingestion.registry_seed_candidate_facets(lower(entity_type));
create index if not exists registry_seed_candidate_facets_postcode_idx
  on ingestion.registry_seed_candidate_facets(postcode);
create index if not exists registry_seed_candidate_facets_dgr_idx
  on ingestion.registry_seed_candidate_facets(has_dgr);
create index if not exists registry_seed_candidate_facets_name_trgm_idx
  on ingestion.registry_seed_candidate_facets
  using gin(lower(entity_name) extensions.gin_trgm_ops);
create index if not exists registry_seed_candidate_facets_native_trgm_idx
  on ingestion.registry_seed_candidate_facets
  using gin(native_id extensions.gin_trgm_ops);

create or replace function ingestion.index_registry_seed_candidate_facets() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  extracted jsonb;
  candidate ingestion.registry_seed_candidates;
begin
  select coalesce(
    jsonb_object_agg(assertion->>'field', assertion->'value')
      filter (where assertion->>'field' is not null),
    '{}'::jsonb
  ) into extracted
  from jsonb_array_elements(new.payload->'assertions') assertion;

  select * into strict candidate
  from ingestion.registry_seed_candidates where id = new.candidate_id;

  insert into ingestion.registry_seed_candidate_facets(
    version_id, candidate_id, source_id, resource_id, native_id,
    entity_name, entity_type, postcode, has_dgr
  ) values (
    new.id,
    new.candidate_id,
    candidate.source_id,
    candidate.resource_id,
    candidate.native_id,
    extracted->>'entity_name',
    extracted#>>'{abr_entity_type,text}',
    extracted#>>'{abr_main_business_location,postcode}',
    extracted ? 'abr_dgr'
      and jsonb_typeof(extracted->'abr_dgr') = 'array'
      and jsonb_array_length(extracted->'abr_dgr') > 0
  )
  on conflict (version_id) do update set
    candidate_id = excluded.candidate_id,
    source_id = excluded.source_id,
    resource_id = excluded.resource_id,
    native_id = excluded.native_id,
    entity_name = excluded.entity_name,
    entity_type = excluded.entity_type,
    postcode = excluded.postcode,
    has_dgr = excluded.has_dgr;
  return new;
end $$;

drop trigger if exists index_registry_seed_candidate_facets
  on ingestion.registry_seed_candidate_versions;
create trigger index_registry_seed_candidate_facets
after insert or update of payload on ingestion.registry_seed_candidate_versions
for each row execute function ingestion.index_registry_seed_candidate_facets();

revoke all on function ingestion.index_registry_seed_candidate_facets() from public;

insert into ingestion.registry_seed_candidate_facets(
  version_id, candidate_id, source_id, resource_id, native_id,
  entity_name, entity_type, postcode, has_dgr
)
select cv.id, cv.candidate_id, c.source_id, c.resource_id, c.native_id,
  extracted.facts->>'entity_name',
  extracted.facts#>>'{abr_entity_type,text}',
  extracted.facts#>>'{abr_main_business_location,postcode}',
  extracted.facts ? 'abr_dgr'
    and jsonb_typeof(extracted.facts->'abr_dgr') = 'array'
    and jsonb_array_length(extracted.facts->'abr_dgr') > 0
from (
  select cv.id, cv.candidate_id, cv.payload
  from ingestion.registry_seed_candidate_versions cv
  left join ingestion.registry_seed_candidate_facets existing on existing.version_id = cv.id
  where existing.version_id is null
) cv
join ingestion.registry_seed_candidates c on c.id = cv.candidate_id
cross join lateral (
  select coalesce(
    jsonb_object_agg(assertion->>'field', assertion->'value')
      filter (where assertion->>'field' is not null),
    '{}'::jsonb
  ) facts
  from jsonb_array_elements(cv.payload->'assertions') assertion
) extracted
on conflict (version_id) do nothing;

analyze ingestion.registry_seed_candidate_facets;

create or replace function community_orgs.registry_seed_triage_queue(
  p_release text default null,
  p_version text default null,
  p_decision text default null,
  p_offset integer default 0,
  p_search text default '',
  p_entity_type text default 'all',
  p_postcode text default '',
  p_dgr text default 'all',
  p_match text default 'all'
) returns jsonb language plpgsql stable security definer
set search_path = '' set plan_cache_mode = force_custom_plan as $$
declare
  selected_release bigint;
  result jsonb;
begin
  if community_orgs.is_data_steward() is distinct from true then
    raise exception 'Data Steward access required' using errcode = '42501';
  end if;
  if p_release is not null and p_release !~ '^[1-9][0-9]*$' then
    raise exception 'Invalid registry release' using errcode = '22023';
  end if;
  if p_version is not null and p_version !~ '^[1-9][0-9]*$' then
    raise exception 'Invalid registry candidate version' using errcode = '22023';
  end if;
  if coalesce(p_decision, 'all') not in ('all', 'pending', 'include', 'exclude', 'defer', 'link')
    or coalesce(p_offset, 0) not between 0 and 1000000
    or length(btrim(coalesce(p_search, ''))) > 100
    or coalesce(p_entity_type, 'all') not in (
      'all', 'exclude_private_company', 'private_company',
      'other_incorporated_entity', 'public_company'
    )
    or (coalesce(p_postcode, '') <> '' and p_postcode !~ '^[0-9]{4}$')
    or coalesce(p_dgr, 'all') not in ('all', 'present', 'absent')
    or coalesce(p_match, 'all') not in ('all', 'strong', 'weak', 'any', 'none') then
    raise exception 'Invalid registry queue filter' using errcode = '22023';
  end if;

  selected_release := p_release::bigint;
  if selected_release is null then
    select r.id into selected_release
    from ingestion.registry_seed_releases r
    order by r.observed_at desc, r.id desc limit 1;
  end if;

  with filtered_versions as materialized (
    select rc.release_id, rc.version_id
    from ingestion.registry_seed_release_candidates rc
    join ingestion.registry_seed_candidate_facets f on f.version_id = rc.version_id
    left join ingestion.registry_seed_triage t on t.version_id = rc.version_id
    where rc.release_id = selected_release
      and (coalesce(p_decision, 'all') = 'all'
        or (p_decision = 'pending' and t.version_id is null)
        or t.decision = p_decision)
      and (btrim(coalesce(p_search, '')) = ''
        or position(lower(btrim(p_search)) in lower(coalesce(f.entity_name, ''))) > 0
        or position(btrim(p_search) in f.native_id) > 0)
      and (coalesce(p_entity_type, 'all') = 'all'
        or (p_entity_type = 'exclude_private_company'
          and lower(coalesce(f.entity_type, '')) <> 'australian private company')
        or (p_entity_type = 'private_company'
          and lower(coalesce(f.entity_type, '')) = 'australian private company')
        or (p_entity_type = 'other_incorporated_entity'
          and lower(coalesce(f.entity_type, '')) = 'other incorporated entity')
        or (p_entity_type = 'public_company'
          and lower(coalesce(f.entity_type, '')) = 'australian public company'))
      and (coalesce(p_postcode, '') = '' or f.postcode = p_postcode)
      and (coalesce(p_dgr, 'all') = 'all'
        or (p_dgr = 'present' and f.has_dgr)
        or (p_dgr = 'absent' and not f.has_dgr))
      and (coalesce(p_match, 'all') = 'all'
        or (p_match in ('strong', 'any') and exists(
          select 1 from ingestion.registry_seed_resolution_keys sk
          join ingestion.registry_seed_resolution_keys other_key
            on other_key.scheme = sk.scheme
            and other_key.jurisdiction = sk.jurisdiction
            and other_key.normalized_value = sk.normalized_value
            and other_key.version_id <> sk.version_id
          where sk.version_id = rc.version_id
            and (p_match = 'any' or sk.strength = 'strong')
        ))
        or (p_match = 'weak'
          and not exists(
            select 1 from ingestion.registry_seed_resolution_keys sk
            join ingestion.registry_seed_resolution_keys other_key
              on other_key.scheme = sk.scheme
              and other_key.jurisdiction = sk.jurisdiction
              and other_key.normalized_value = sk.normalized_value
              and other_key.version_id <> sk.version_id
            where sk.version_id = rc.version_id and sk.strength = 'strong'
          )
          and exists(
            select 1 from ingestion.registry_seed_resolution_keys sk
            join ingestion.registry_seed_resolution_keys other_key
              on other_key.scheme = sk.scheme
              and other_key.jurisdiction = sk.jurisdiction
              and other_key.normalized_value = sk.normalized_value
              and other_key.version_id <> sk.version_id
            where sk.version_id = rc.version_id and sk.strength = 'weak'
          ))
        or (p_match = 'none' and not exists(
          select 1 from ingestion.registry_seed_resolution_keys sk
          join ingestion.registry_seed_resolution_keys other_key
            on other_key.scheme = sk.scheme
            and other_key.jurisdiction = sk.jurisdiction
            and other_key.normalized_value = sk.normalized_value
            and other_key.version_id <> sk.version_id
          where sk.version_id = rc.version_id
        )))
  ), releases as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id::text,
      'release_key', r.release_key,
      'source_id', r.source_id,
      'resource_id', r.resource_id,
      'observed_at', r.observed_at,
      'completion', r.completion,
      'candidate_count', r.candidate_count,
      'raw_removed_at', r.raw_removed_at
    ) order by r.observed_at desc, r.id desc), '[]'::jsonb) value
    from (select * from ingestion.registry_seed_releases order by observed_at desc, id desc limit 100) r
  ), total as (
    select count(*) value from filtered_versions
  ), page_rows as materialized (
    select fv.release_id, fv.version_id, rc.in_scope,
      f.candidate_id, f.native_id, f.source_id, f.resource_id,
      f.entity_name, f.entity_type, f.postcode, f.has_dgr,
      t.revision, t.decision,
      exists(select 1 from ingestion.registry_seed_promotions p
        where p.release_id = fv.release_id and p.version_id = fv.version_id) promoted,
      case
        when exists(
          select 1 from ingestion.registry_seed_resolution_keys sk
          join ingestion.registry_seed_resolution_keys other_key
            on other_key.scheme = sk.scheme
            and other_key.jurisdiction = sk.jurisdiction
            and other_key.normalized_value = sk.normalized_value
            and other_key.version_id <> sk.version_id
          where sk.version_id = fv.version_id and sk.strength = 'strong'
        ) then 'strong'
        when exists(
          select 1 from ingestion.registry_seed_resolution_keys sk
          join ingestion.registry_seed_resolution_keys other_key
            on other_key.scheme = sk.scheme
            and other_key.jurisdiction = sk.jurisdiction
            and other_key.normalized_value = sk.normalized_value
            and other_key.version_id <> sk.version_id
          where sk.version_id = fv.version_id and sk.strength = 'weak'
        ) then 'weak'
        else 'none'
      end match_strength
    from filtered_versions fv
    join ingestion.registry_seed_release_candidates rc
      on rc.release_id = fv.release_id and rc.version_id = fv.version_id
    join ingestion.registry_seed_candidate_facets f on f.version_id = fv.version_id
    left join ingestion.registry_seed_triage t on t.version_id = fv.version_id
    order by fv.version_id limit 50 offset coalesce(p_offset, 0)
  ), records as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'version_id', q.version_id::text,
      'native_id', q.native_id,
      'name', coalesce(q.entity_name, q.native_id),
      'decision', coalesce(q.decision, 'pending'),
      'revision', coalesce(q.revision, 0),
      'in_scope', q.in_scope,
      'promoted', q.promoted,
      'entity_type', q.entity_type,
      'postcode', q.postcode,
      'has_dgr', q.has_dgr,
      'match_strength', q.match_strength
    ) order by q.version_id), '[]'::jsonb) value
    from page_rows q
  ), selected as (
    select fv.release_id, fv.version_id, rc.in_scope, rc.selection_reasons,
      f.candidate_id, f.native_id, f.source_id, f.resource_id,
      t.revision, t.decision, t.target_candidate_id, t.target_record_id,
      t.note, t.reviewed_at, cv.payload - 'raw' safe_payload,
      exists(select 1 from ingestion.registry_seed_promotions p
        where p.release_id = fv.release_id and p.version_id = fv.version_id) promoted
    from filtered_versions fv
    join ingestion.registry_seed_release_candidates rc
      on rc.release_id = fv.release_id and rc.version_id = fv.version_id
    join ingestion.registry_seed_candidate_facets f on f.version_id = fv.version_id
    join ingestion.registry_seed_candidate_versions cv on cv.id = fv.version_id
    left join ingestion.registry_seed_triage t on t.version_id = fv.version_id
    where fv.version_id = coalesce(
      p_version::bigint,
      (select p.version_id from page_rows p order by p.version_id limit 1)
    )
  ), suggestions as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'kind', x.kind, 'id', x.id, 'source_id', x.source_id, 'native_id', x.native_id,
      'name', x.entity_name, 'reason', x.reason
    ) order by x.strength, x.kind, x.id), '[]'::jsonb) value
    from (
      select 'candidate' kind, other.id::text id, other.source_id, other.native_id,
        coalesce(other_facet.entity_name, other.native_id) entity_name,
        case
          when bool_or(sk.scheme = 'abn') then 'Exact ABN across registry candidates'
          when bool_or(sk.scheme = 'incorporated_association')
            then 'Exact jurisdiction-scoped incorporation number'
          else 'Same normalised name; weak evidence requiring review'
        end reason,
        min(case when sk.strength = 'strong' then 0 else 1 end) strength
      from selected sf
      join ingestion.registry_seed_resolution_keys sk on sk.version_id = sf.version_id
      join ingestion.registry_seed_resolution_keys other_key
        on other_key.scheme = sk.scheme and other_key.jurisdiction = sk.jurisdiction
        and other_key.normalized_value = sk.normalized_value
        and other_key.version_id <> sk.version_id
      join ingestion.registry_seed_candidate_versions ov on ov.id = other_key.version_id
      join ingestion.registry_seed_candidates other on other.id = ov.candidate_id
      join ingestion.registry_seed_candidate_facets other_facet on other_facet.version_id = ov.id
      group by other.id, other.source_id, other.native_id, other_facet.entity_name
      limit 20
    ) x
  ), detail as (
    select jsonb_build_object(
      'release_id', sf.release_id::text, 'version_id', sf.version_id::text,
      'candidate_id', sf.candidate_id::text, 'native_id', sf.native_id,
      'source_id', sf.source_id, 'resource_id', sf.resource_id,
      'in_scope', sf.in_scope, 'selection_reasons', sf.selection_reasons,
      'payload', sf.safe_payload, 'promoted', sf.promoted,
      'triage', case when sf.decision is null then null else jsonb_build_object(
        'revision', sf.revision, 'decision', sf.decision,
        'target_candidate_id', sf.target_candidate_id::text,
        'target_record_id', sf.target_record_id::text, 'note', sf.note,
        'reviewed_at', sf.reviewed_at) end,
      'suggestions', suggestions.value
    ) value from selected sf cross join suggestions
  )
  select jsonb_build_object(
    'releases', releases.value, 'release_id', selected_release::text,
    'total', total.value, 'offset', coalesce(p_offset, 0),
    'records', records.value, 'detail', detail.value
  ) into result
  from releases cross join total cross join records left join detail on true;
  return result;
end $$;

revoke all on function community_orgs.registry_seed_triage_queue(
  text, text, text, integer, text, text, text, text, text
) from public, anon, service_role, ingestion_worker;
grant execute on function community_orgs.registry_seed_triage_queue(
  text, text, text, integer, text, text, text, text, text
) to authenticated;

comment on table ingestion.registry_seed_candidate_facets is
  'Private, indexed and redacted registry assertion facets used by the bounded triage queue.';
comment on function community_orgs.registry_seed_triage_queue(
  text, text, text, integer, text, text, text, text, text
) is 'Indexed redacted registry seed review queue with server-side cohort filters and cross-source suggestions.';

commit;
