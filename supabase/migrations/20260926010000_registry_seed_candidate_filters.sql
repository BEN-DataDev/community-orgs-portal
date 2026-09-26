-- Keep the first operational cohort bounded by filtering the complete private
-- release in SQL before pagination. Provider raw payloads remain inaccessible;
-- filters operate only on the redacted mapped assertions already exposed by the
-- triage queue.
drop function community_orgs.registry_seed_triage_queue(text, text, text, integer);

create function community_orgs.registry_seed_triage_queue(
  p_release text default null,
  p_version text default null,
  p_decision text default null,
  p_offset integer default 0,
  p_search text default '',
  p_entity_type text default 'all',
  p_postcode text default '',
  p_dgr text default 'all',
  p_match text default 'all'
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
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

  with candidate_rows as materialized (
    select rc.release_id, rc.version_id, rc.in_scope, rc.selection_reasons,
      c.id candidate_id, c.native_id, c.source_id, c.resource_id,
      cv.payload - 'raw' safe_payload, facts.value facts,
      t.revision, t.decision, t.target_candidate_id, t.target_record_id,
      t.note, t.reviewed_at,
      exists(select 1 from ingestion.registry_seed_promotions p
        where p.release_id = rc.release_id and p.version_id = rc.version_id) promoted
    from ingestion.registry_seed_release_candidates rc
    join ingestion.registry_seed_candidate_versions cv on cv.id = rc.version_id
    join ingestion.registry_seed_candidates c on c.id = cv.candidate_id
    left join ingestion.registry_seed_triage t on t.version_id = rc.version_id
    cross join lateral (
      select coalesce(jsonb_object_agg(a->>'field', a->'value')
        filter (where a->>'field' is not null), '{}'::jsonb) value
      from jsonb_array_elements(cv.payload->'assertions') a
    ) facts
    where rc.release_id = selected_release
  ), filtered as materialized (
    select * from candidate_rows c
    where (coalesce(p_decision, 'all') = 'all'
        or (p_decision = 'pending' and c.decision is null)
        or c.decision = p_decision)
      and (btrim(coalesce(p_search, '')) = ''
        or position(lower(btrim(p_search)) in lower(coalesce(c.facts->>'entity_name', ''))) > 0
        or position(btrim(p_search) in c.native_id) > 0)
      and (coalesce(p_entity_type, 'all') = 'all'
        or (p_entity_type = 'exclude_private_company'
          and lower(coalesce(c.facts#>>'{abr_entity_type,text}', '')) <> 'australian private company')
        or (p_entity_type = 'private_company'
          and lower(coalesce(c.facts#>>'{abr_entity_type,text}', '')) = 'australian private company')
        or (p_entity_type = 'other_incorporated_entity'
          and lower(coalesce(c.facts#>>'{abr_entity_type,text}', '')) = 'other incorporated entity')
        or (p_entity_type = 'public_company'
          and lower(coalesce(c.facts#>>'{abr_entity_type,text}', '')) = 'australian public company'))
      and (coalesce(p_postcode, '') = ''
        or c.facts#>>'{abr_main_business_location,postcode}' = p_postcode)
      and (coalesce(p_dgr, 'all') = 'all'
        or (p_dgr = 'present' and c.facts ? 'abr_dgr'
          and jsonb_typeof(c.facts->'abr_dgr') = 'array'
          and jsonb_array_length(c.facts->'abr_dgr') > 0)
        or (p_dgr = 'absent' and not (c.facts ? 'abr_dgr')))
      and (coalesce(p_match, 'all') = 'all'
        or (p_match in ('strong', 'any') and exists(
          select 1 from ingestion.registry_seed_resolution_keys sk
          join ingestion.registry_seed_resolution_keys other_key
            on other_key.scheme = sk.scheme
            and other_key.jurisdiction = sk.jurisdiction
            and other_key.normalized_value = sk.normalized_value
            and other_key.version_id <> sk.version_id
          where sk.version_id = c.version_id
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
            where sk.version_id = c.version_id and sk.strength = 'strong'
          )
          and exists(
            select 1 from ingestion.registry_seed_resolution_keys sk
            join ingestion.registry_seed_resolution_keys other_key
              on other_key.scheme = sk.scheme
              and other_key.jurisdiction = sk.jurisdiction
              and other_key.normalized_value = sk.normalized_value
              and other_key.version_id <> sk.version_id
            where sk.version_id = c.version_id and sk.strength = 'weak'
          ))
        or (p_match = 'none' and not exists(
          select 1 from ingestion.registry_seed_resolution_keys sk
          join ingestion.registry_seed_resolution_keys other_key
            on other_key.scheme = sk.scheme
            and other_key.jurisdiction = sk.jurisdiction
            and other_key.normalized_value = sk.normalized_value
            and other_key.version_id <> sk.version_id
          where sk.version_id = c.version_id
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
    select count(*) value from filtered
  ), page_rows as materialized (
    select f.*,
      case
        when exists(
          select 1 from ingestion.registry_seed_resolution_keys sk
          join ingestion.registry_seed_resolution_keys other_key
            on other_key.scheme = sk.scheme
            and other_key.jurisdiction = sk.jurisdiction
            and other_key.normalized_value = sk.normalized_value
            and other_key.version_id <> sk.version_id
          where sk.version_id = f.version_id and sk.strength = 'strong'
        ) then 'strong'
        when exists(
          select 1 from ingestion.registry_seed_resolution_keys sk
          join ingestion.registry_seed_resolution_keys other_key
            on other_key.scheme = sk.scheme
            and other_key.jurisdiction = sk.jurisdiction
            and other_key.normalized_value = sk.normalized_value
            and other_key.version_id <> sk.version_id
          where sk.version_id = f.version_id and sk.strength = 'weak'
        ) then 'weak'
        else 'none'
      end match_strength
    from filtered f order by version_id limit 50 offset coalesce(p_offset, 0)
  ), records as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'version_id', q.version_id::text,
      'native_id', q.native_id,
      'name', coalesce(q.facts->>'entity_name', q.native_id),
      'decision', coalesce(q.decision, 'pending'),
      'revision', coalesce(q.revision, 0),
      'in_scope', q.in_scope,
      'promoted', q.promoted,
      'entity_type', q.facts#>>'{abr_entity_type,text}',
      'postcode', q.facts#>>'{abr_main_business_location,postcode}',
      'has_dgr', q.facts ? 'abr_dgr',
      'match_strength', q.match_strength
    ) order by q.version_id), '[]'::jsonb) value
    from page_rows q
  ), selected as (
    select * from filtered f
    where f.version_id = coalesce(
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
        coalesce(ofacts->>'entity_name', other.native_id) entity_name,
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
      cross join lateral (select coalesce(jsonb_object_agg(a->>'field', a->'value'), '{}'::jsonb) value
        from jsonb_array_elements(ov.payload->'assertions') a) o(ofacts)
      group by other.id, other.source_id, other.native_id, ofacts
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

comment on function community_orgs.registry_seed_triage_queue(
  text, text, text, integer, text, text, text, text, text
) is 'Redacted bounded registry seed review queue with server-side cohort filters and cross-source suggestions.';
