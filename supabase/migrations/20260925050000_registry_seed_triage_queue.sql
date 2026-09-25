-- Phase 7 / P35: expose a bounded, redacted registry-seed triage queue. Raw
-- provider payloads remain private; suggestions are evidence, never auto-links.
create table ingestion.registry_seed_resolution_keys (
  version_id bigint not null references ingestion.registry_seed_candidate_versions(id) on delete restrict,
  strength text not null check (strength in ('strong', 'weak')),
  scheme text not null check (scheme in ('abn', 'incorporated_association', 'normalised_name')),
  jurisdiction text not null,
  normalized_value text not null check (length(normalized_value) between 1 and 500),
  primary key (version_id, scheme, jurisdiction, normalized_value)
);

create index registry_seed_resolution_key_lookup
  on ingestion.registry_seed_resolution_keys(scheme, jurisdiction, normalized_value, version_id);
alter table ingestion.registry_seed_resolution_keys enable row level security;
revoke all on ingestion.registry_seed_resolution_keys from public, anon, authenticated,
  service_role, ingestion_worker;

create function ingestion.index_registry_seed_resolution_keys() returns trigger
language plpgsql security definer set search_path = '' as $$
declare facts jsonb;
begin
  select coalesce(jsonb_object_agg(a->>'field', a->'value'), '{}'::jsonb) into facts
  from jsonb_array_elements(new.payload->'assertions') a;
  if facts->>'abn' ~ '^[0-9]{11}$' then
    insert into ingestion.registry_seed_resolution_keys(
      version_id, strength, scheme, jurisdiction, normalized_value
    ) values (new.id, 'strong', 'abn', 'AU', facts->>'abn') on conflict do nothing;
  end if;
  if coalesce(facts->>'csv_incorporation_number', '') <> ''
    and facts->>'csv_incorporation_jurisdiction' in ('NSW', 'AU-NSW') then
    insert into ingestion.registry_seed_resolution_keys(
      version_id, strength, scheme, jurisdiction, normalized_value
    ) values (
      new.id, 'strong', 'incorporated_association', 'AU-NSW',
      btrim(facts->>'csv_incorporation_number')
    ) on conflict do nothing;
  end if;
  if length(regexp_replace(upper(facts->>'entity_name'), '[^A-Z0-9]', '', 'g')) >= 5 then
    insert into ingestion.registry_seed_resolution_keys(
      version_id, strength, scheme, jurisdiction, normalized_value
    ) values (
      new.id, 'weak', 'normalised_name', '',
      regexp_replace(upper(facts->>'entity_name'), '[^A-Z0-9]', '', 'g')
    ) on conflict do nothing;
  end if;
  return new;
end $$;

create trigger index_registry_seed_resolution_keys
after insert on ingestion.registry_seed_candidate_versions for each row
execute function ingestion.index_registry_seed_resolution_keys();

revoke all on function ingestion.index_registry_seed_resolution_keys() from public;

with versions as (
  select cv.id, coalesce(jsonb_object_agg(a->>'field', a->'value'), '{}'::jsonb) facts
  from ingestion.registry_seed_candidate_versions cv
  left join lateral jsonb_array_elements(cv.payload->'assertions') a on true
  group by cv.id
)
insert into ingestion.registry_seed_resolution_keys(
  version_id, strength, scheme, jurisdiction, normalized_value
)
select id, 'strong', 'abn', 'AU', facts->>'abn' from versions
where facts->>'abn' ~ '^[0-9]{11}$'
union all
select id, 'strong', 'incorporated_association', 'AU-NSW',
  btrim(facts->>'csv_incorporation_number') from versions
where coalesce(facts->>'csv_incorporation_number', '') <> ''
  and facts->>'csv_incorporation_jurisdiction' in ('NSW', 'AU-NSW')
union all
select id, 'weak', 'normalised_name', '',
  regexp_replace(upper(facts->>'entity_name'), '[^A-Z0-9]', '', 'g') from versions
where length(regexp_replace(upper(facts->>'entity_name'), '[^A-Z0-9]', '', 'g')) >= 5;

create function community_orgs.registry_seed_triage_queue(
  p_release text default null,
  p_version text default null,
  p_decision text default null,
  p_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  selected_release bigint;
  selected_version bigint;
  total_count integer;
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
    or coalesce(p_offset, 0) not between 0 and 1000000 then
    raise exception 'Invalid registry queue filter' using errcode = '22023';
  end if;

  selected_release := p_release::bigint;
  if selected_release is null then
    select r.id into selected_release
    from ingestion.registry_seed_releases r
    order by r.observed_at desc, r.id desc limit 1;
  end if;

  select count(*) into total_count
  from ingestion.registry_seed_release_candidates rc
  left join ingestion.registry_seed_triage t on t.version_id = rc.version_id
  where rc.release_id = selected_release
    and (coalesce(p_decision, 'all') = 'all'
      or (p_decision = 'pending' and t.version_id is null)
      or t.decision = p_decision);

  if p_version is not null then
    select rc.version_id into selected_version
    from ingestion.registry_seed_release_candidates rc
    where rc.release_id = selected_release and rc.version_id = p_version::bigint;
  else
    select rc.version_id into selected_version
    from ingestion.registry_seed_release_candidates rc
    left join ingestion.registry_seed_triage t on t.version_id = rc.version_id
    where rc.release_id = selected_release
      and (coalesce(p_decision, 'all') = 'all'
        or (p_decision = 'pending' and t.version_id is null)
        or t.decision = p_decision)
    order by rc.version_id limit 1 offset coalesce(p_offset, 0);
  end if;

  with releases as (
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
  ), records as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'version_id', q.version_id::text,
      'native_id', q.native_id,
      'name', q.entity_name,
      'decision', coalesce(q.decision, 'pending'),
      'revision', coalesce(q.revision, 0),
      'in_scope', q.in_scope,
      'promoted', q.promoted
    ) order by q.version_id), '[]'::jsonb) value
    from (
      select rc.version_id, c.native_id,
        coalesce((select a->>'value' from jsonb_array_elements(cv.payload->'assertions') a
          where a->>'field' = 'entity_name' limit 1), c.native_id) entity_name,
        t.decision, t.revision, rc.in_scope,
        exists(select 1 from ingestion.registry_seed_promotions p
          where p.release_id = rc.release_id and p.version_id = rc.version_id) promoted
      from ingestion.registry_seed_release_candidates rc
      join ingestion.registry_seed_candidate_versions cv on cv.id = rc.version_id
      join ingestion.registry_seed_candidates c on c.id = cv.candidate_id
      left join ingestion.registry_seed_triage t on t.version_id = rc.version_id
      where rc.release_id = selected_release
        and (coalesce(p_decision, 'all') = 'all'
          or (p_decision = 'pending' and t.version_id is null)
          or t.decision = p_decision)
      order by rc.version_id limit 50 offset coalesce(p_offset, 0)
    ) q
  ), selected as (
    select rc.release_id, rc.version_id, rc.in_scope, rc.selection_reasons,
      c.id candidate_id, c.native_id, c.source_id, c.resource_id,
      cv.payload - 'raw' safe_payload, t.revision, t.decision, t.target_candidate_id,
      t.target_record_id, t.note, t.reviewed_at,
      exists(select 1 from ingestion.registry_seed_promotions p
        where p.release_id = rc.release_id and p.version_id = rc.version_id) promoted
    from ingestion.registry_seed_release_candidates rc
    join ingestion.registry_seed_candidate_versions cv on cv.id = rc.version_id
    join ingestion.registry_seed_candidates c on c.id = cv.candidate_id
    left join ingestion.registry_seed_triage t on t.version_id = rc.version_id
    where rc.release_id = selected_release and rc.version_id = selected_version
  ), selected_facts as (
    select s.*, coalesce(jsonb_object_agg(a->>'field', a->'value')
      filter (where a->>'field' is not null), '{}'::jsonb) facts
    from selected s left join lateral jsonb_array_elements(s.safe_payload->'assertions') a on true
    group by s.release_id, s.version_id, s.in_scope, s.selection_reasons, s.candidate_id,
      s.native_id, s.source_id, s.resource_id, s.safe_payload, s.revision, s.decision,
      s.target_candidate_id, s.target_record_id, s.note, s.reviewed_at, s.promoted
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
      from selected_facts sf
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
    ) value from selected_facts sf cross join suggestions
  )
  select jsonb_build_object(
    'releases', releases.value, 'release_id', selected_release::text,
    'total', total_count, 'offset', coalesce(p_offset, 0),
    'records', records.value, 'detail', detail.value
  ) into result
  from releases cross join records left join detail on true;
  return result;
end $$;

revoke all on function community_orgs.registry_seed_triage_queue(text, text, text, integer)
  from public, anon, service_role, ingestion_worker;
grant execute on function community_orgs.registry_seed_triage_queue(text, text, text, integer)
  to authenticated;

comment on function community_orgs.registry_seed_triage_queue(text, text, text, integer) is
  'Redacted bounded registry seed review queue with exact-identifier and weak-name suggestions.';
