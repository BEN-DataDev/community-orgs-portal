-- Candidate vetting starts only after all three establishment sources have a
-- complete acquisition. ABR candidates are then bounded to plausible community
-- entity types or genuine ACNC/NSW cross-source suggestions.
begin;

create index if not exists field_assertions_abn_value_idx
  on ingestion.field_assertions ((regexp_replace(value #>> '{}', '[^0-9]', '', 'g')))
  where field = 'abn';
create index if not exists field_assertions_normalised_name_idx
  on ingestion.field_assertions
  ((regexp_replace(upper(value #>> '{}'), '[^A-Z0-9]', '', 'g')))
  where field = 'entity_name';

create view ingestion.registry_seed_cross_source_matches
with (security_invoker = true) as
with raw_matches as (
  select abr.version_id candidate_version_id, 'candidate'::text target_kind,
    other.candidate_id target_id, other.source_id, other.native_id,
    coalesce(other.entity_name, other.native_id) name,
    sk.strength,
    case
      when sk.scheme = 'abn' then 'Exact ABN in NSW incorporated-associations candidates'
      when sk.scheme = 'incorporated_association' then 'Exact NSW incorporation number'
      else 'Same normalised name in NSW incorporated-associations candidates'
    end reason
  from ingestion.registry_seed_candidate_facets abr
  join ingestion.registry_seed_resolution_keys sk on sk.version_id = abr.version_id
  join ingestion.registry_seed_resolution_keys other_key
    on other_key.scheme = sk.scheme
    and other_key.jurisdiction = sk.jurisdiction
    and other_key.normalized_value = sk.normalized_value
    and other_key.version_id <> sk.version_id
  join ingestion.registry_seed_candidate_facets other on other.version_id = other_key.version_id
  where abr.source_id = 'abr-bulk'
    and other.source_id = 'nsw-incorporated-associations'

  union all

  select abr.version_id, 'record', record.id, record.source_id, record.native_id,
    coalesce(name_assertion.value #>> '{}', record.native_id), 'strong',
    'Exact ABN in the ACNC Charity Register'
  from ingestion.registry_seed_candidate_facets abr
  join ingestion.field_assertions abn_assertion
    on abn_assertion.field = 'abn'
    and regexp_replace(abn_assertion.value #>> '{}', '[^0-9]', '', 'g') = abr.native_id
  join ingestion.source_record_versions source_version on source_version.id = abn_assertion.version_id
  join ingestion.source_records record on record.id = source_version.record_id
    and record.source_id = 'acnc-register'
  left join ingestion.field_assertions name_assertion
    on name_assertion.version_id = source_version.id and name_assertion.field = 'entity_name'
  where abr.source_id = 'abr-bulk'

  union all

  select abr.version_id, 'record', record.id, record.source_id, record.native_id,
    name_assertion.value #>> '{}', 'weak',
    'Same normalised name in the ACNC Charity Register; verify before linking'
  from ingestion.registry_seed_candidate_facets abr
  join ingestion.field_assertions name_assertion
    on name_assertion.field = 'entity_name'
    and regexp_replace(upper(name_assertion.value #>> '{}'), '[^A-Z0-9]', '', 'g') =
      regexp_replace(upper(coalesce(abr.entity_name, '')), '[^A-Z0-9]', '', 'g')
  join ingestion.source_record_versions source_version on source_version.id = name_assertion.version_id
  join ingestion.source_records record on record.id = source_version.record_id
    and record.source_id = 'acnc-register'
  where abr.source_id = 'abr-bulk'
    and length(regexp_replace(upper(coalesce(abr.entity_name, '')), '[^A-Z0-9]', '', 'g')) >= 5
), ranked as (
  select *, row_number() over (
    partition by candidate_version_id, target_kind, target_id
    order by case strength when 'strong' then 0 else 1 end, reason
  ) match_rank
  from raw_matches
)
select candidate_version_id, target_kind, target_id, source_id, native_id,
  name, strength, reason
from ranked where match_rank = 1;

revoke all on ingestion.registry_seed_cross_source_matches
  from public, anon, authenticated, service_role, ingestion_worker;

create function community_orgs.registry_seed_vetting_readiness()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if community_orgs.is_data_steward() is distinct from true then
    raise exception 'Data Steward access required' using errcode='42501';
  end if;
  with required(source_id, artifact_kind, ready) as (
    values
      ('abr-bulk', 'registry_seed_release', exists(
        select 1 from ingestion.registry_seed_releases r
        where r.source_id = 'abr-bulk' and r.completion = 'complete' and r.candidate_count > 0
      )),
      ('acnc-register', 'ingestion_run', exists(
        select 1 from ingestion.ingestion_runs r
        where r.source_id = 'acnc-register' and r.completion = 'complete'
          and exists(select 1 from ingestion.run_records rr where rr.run_id = r.id)
      )),
      ('nsw-incorporated-associations', 'registry_seed_release', exists(
        select 1 from ingestion.registry_seed_releases r
        where r.source_id = 'nsw-incorporated-associations'
          and r.completion = 'complete' and r.candidate_count > 0
      ))
  )
  select jsonb_build_object(
    'ready', bool_and(ready),
    'sources', jsonb_agg(jsonb_build_object(
      'source_id', source_id, 'artifact_kind', artifact_kind, 'ready', ready
    ) order by source_id)
  ) into result from required;
  return result;
end
$$;

revoke all on function community_orgs.registry_seed_vetting_readiness()
  from public, anon, service_role, ingestion_worker;
grant execute on function community_orgs.registry_seed_vetting_readiness() to authenticated;

create or replace function community_orgs.registry_seed_triage_queue(
  p_release text default null,
  p_version text default null,
  p_decision text default null,
  p_offset integer default 0,
  p_search text default '',
  p_entity_type text default 'community_candidate',
  p_postcode text default '',
  p_dgr text default 'all',
  p_match text default 'all'
) returns jsonb language plpgsql stable security definer
set search_path = '' set plan_cache_mode = force_custom_plan as $$
declare selected_release bigint; result jsonb;
begin
  if community_orgs.is_data_steward() is distinct from true then
    raise exception 'Data Steward access required' using errcode = '42501';
  end if;
  if p_release is not null and p_release !~ '^[1-9][0-9]*$'
    or p_version is not null and p_version !~ '^[1-9][0-9]*$'
    or coalesce(p_decision, 'all') not in ('all','pending','include','exclude','defer','link')
    or coalesce(p_offset, 0) not between 0 and 1000000
    or length(btrim(coalesce(p_search, ''))) > 100
    or coalesce(p_entity_type, 'community_candidate') not in (
      'community_candidate','all','exclude_private_company','private_company',
      'other_incorporated_entity','other_unincorporated_entity','public_company'
    )
    or coalesce(p_postcode, '') <> '' and p_postcode !~ '^[0-9]{4}$'
    or coalesce(p_dgr, 'all') not in ('all','present','absent')
    or coalesce(p_match, 'all') not in ('all','strong','weak','any','none') then
    raise exception 'Invalid registry queue filter' using errcode = '22023';
  end if;

  selected_release := p_release::bigint;
  if selected_release is null then
    select r.id into selected_release from ingestion.registry_seed_releases r
    where r.source_id = 'abr-bulk'
    order by r.observed_at desc, r.id desc limit 1;
  end if;

  with filtered_versions as materialized (
    select rc.release_id, rc.version_id
    from ingestion.registry_seed_release_candidates rc
    join ingestion.registry_seed_candidate_facets f on f.version_id = rc.version_id
    left join ingestion.registry_seed_triage t on t.version_id = rc.version_id
    where rc.release_id = selected_release
      and (coalesce(p_decision,'all')='all'
        or p_decision='pending' and t.version_id is null or t.decision=p_decision)
      and (btrim(coalesce(p_search,''))=''
        or position(lower(btrim(p_search)) in lower(coalesce(f.entity_name,'')))>0
        or position(btrim(p_search) in f.native_id)>0)
      and (coalesce(p_entity_type,'community_candidate')='all'
        or p_entity_type='community_candidate' and (
          lower(coalesce(f.entity_type,'')) in (
            'other incorporated entity','other unincorporated entity'
          ) or exists(select 1 from ingestion.registry_seed_cross_source_matches m
            where m.candidate_version_id=rc.version_id)
        )
        or p_entity_type='exclude_private_company'
          and lower(coalesce(f.entity_type,''))<>'australian private company'
        or p_entity_type='private_company'
          and lower(coalesce(f.entity_type,''))='australian private company'
        or p_entity_type='other_incorporated_entity'
          and lower(coalesce(f.entity_type,''))='other incorporated entity'
        or p_entity_type='other_unincorporated_entity'
          and lower(coalesce(f.entity_type,''))='other unincorporated entity'
        or p_entity_type='public_company'
          and lower(coalesce(f.entity_type,''))='australian public company')
      and (coalesce(p_postcode,'')='' or f.postcode=p_postcode)
      and (coalesce(p_dgr,'all')='all' or p_dgr='present' and f.has_dgr
        or p_dgr='absent' and not f.has_dgr)
      and (coalesce(p_match,'all')='all'
        or p_match in ('strong','any') and exists(
          select 1 from ingestion.registry_seed_cross_source_matches m
          where m.candidate_version_id=rc.version_id
            and (p_match='any' or m.strength='strong'))
        or p_match='weak' and not exists(
          select 1 from ingestion.registry_seed_cross_source_matches m
          where m.candidate_version_id=rc.version_id and m.strength='strong')
          and exists(select 1 from ingestion.registry_seed_cross_source_matches m
            where m.candidate_version_id=rc.version_id and m.strength='weak')
        or p_match='none' and not exists(
          select 1 from ingestion.registry_seed_cross_source_matches m
          where m.candidate_version_id=rc.version_id))
  ), releases as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',r.id::text,'release_key',r.release_key,'source_id',r.source_id,
      'resource_id',r.resource_id,'observed_at',r.observed_at,'completion',r.completion,
      'candidate_count',r.candidate_count,'raw_removed_at',r.raw_removed_at
    ) order by r.observed_at desc,r.id desc),'[]'::jsonb) value
    from (select * from ingestion.registry_seed_releases
      where source_id='abr-bulk' order by observed_at desc,id desc limit 100) r
  ), total as (select count(*) value from filtered_versions),
  page_rows as materialized (
    select fv.release_id,fv.version_id,rc.in_scope,f.candidate_id,f.native_id,
      f.source_id,f.resource_id,f.entity_name,f.entity_type,f.postcode,f.has_dgr,
      t.revision,t.decision,
      exists(select 1 from ingestion.registry_seed_promotions p
        where p.release_id=fv.release_id and p.version_id=fv.version_id) promoted,
      case
        when exists(select 1 from ingestion.registry_seed_cross_source_matches m
          where m.candidate_version_id=fv.version_id and m.strength='strong') then 'strong'
        when exists(select 1 from ingestion.registry_seed_cross_source_matches m
          where m.candidate_version_id=fv.version_id and m.strength='weak') then 'weak'
        else 'none' end match_strength
    from filtered_versions fv
    join ingestion.registry_seed_release_candidates rc
      on rc.release_id=fv.release_id and rc.version_id=fv.version_id
    join ingestion.registry_seed_candidate_facets f on f.version_id=fv.version_id
    left join ingestion.registry_seed_triage t on t.version_id=fv.version_id
    order by fv.version_id limit 50 offset coalesce(p_offset,0)
  ), records as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'version_id',q.version_id::text,'native_id',q.native_id,
      'name',coalesce(q.entity_name,q.native_id),'decision',coalesce(q.decision,'pending'),
      'revision',coalesce(q.revision,0),'in_scope',q.in_scope,'promoted',q.promoted,
      'entity_type',q.entity_type,'postcode',q.postcode,'has_dgr',q.has_dgr,
      'match_strength',q.match_strength) order by q.version_id),'[]'::jsonb) value
    from page_rows q
  ), selected as (
    select fv.release_id,fv.version_id,rc.in_scope,rc.selection_reasons,
      f.candidate_id,f.native_id,f.source_id,f.resource_id,t.revision,t.decision,
      t.target_candidate_id,t.target_record_id,t.note,t.reviewed_at,
      cv.payload-'raw' safe_payload,
      exists(select 1 from ingestion.registry_seed_promotions p
        where p.release_id=fv.release_id and p.version_id=fv.version_id) promoted
    from filtered_versions fv
    join ingestion.registry_seed_release_candidates rc
      on rc.release_id=fv.release_id and rc.version_id=fv.version_id
    join ingestion.registry_seed_candidate_facets f on f.version_id=fv.version_id
    join ingestion.registry_seed_candidate_versions cv on cv.id=fv.version_id
    left join ingestion.registry_seed_triage t on t.version_id=fv.version_id
    where fv.version_id=coalesce(p_version::bigint,
      (select p.version_id from page_rows p order by p.version_id limit 1))
  ), suggestions as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'kind',m.target_kind,'id',m.target_id::text,'source_id',m.source_id,
      'native_id',m.native_id,'name',m.name,'reason',m.reason
    ) order by case m.strength when 'strong' then 0 else 1 end,m.source_id,m.target_id),'[]'::jsonb) value
    from selected s join ingestion.registry_seed_cross_source_matches m
      on m.candidate_version_id=s.version_id
  ), detail as (
    select jsonb_build_object(
      'release_id',s.release_id::text,'version_id',s.version_id::text,
      'candidate_id',s.candidate_id::text,'native_id',s.native_id,
      'source_id',s.source_id,'resource_id',s.resource_id,'in_scope',s.in_scope,
      'selection_reasons',s.selection_reasons,'payload',s.safe_payload,'promoted',s.promoted,
      'triage',case when s.decision is null then null else jsonb_build_object(
        'revision',s.revision,'decision',s.decision,
        'target_candidate_id',s.target_candidate_id::text,
        'target_record_id',s.target_record_id::text,'note',s.note,
        'reviewed_at',s.reviewed_at) end,'suggestions',suggestions.value
    ) value from selected s cross join suggestions
  )
  select jsonb_build_object('releases',releases.value,'release_id',selected_release::text,
    'total',total.value,'offset',coalesce(p_offset,0),'records',records.value,
    'detail',detail.value) into result
  from releases cross join total cross join records left join detail on true;
  return result;
end $$;

revoke all on function community_orgs.registry_seed_triage_queue(
  text,text,text,integer,text,text,text,text,text
) from public,anon,service_role,ingestion_worker;
grant execute on function community_orgs.registry_seed_triage_queue(
  text,text,text,integer,text,text,text,text,text
) to authenticated;

alter function community_orgs.save_registry_seed_triage(text,integer,text,text,text,text)
  rename to save_registry_seed_triage_before_three_source_gate;
create function community_orgs.save_registry_seed_triage(
  p_version text,p_revision integer,p_decision text,p_target_candidate text,
  p_target_record text,p_note text
) returns void language plpgsql security definer set search_path='' as $$
begin
  if community_orgs.registry_seed_vetting_readiness()->>'ready' <> 'true' then
    raise exception 'Complete ABR, ACNC and NSW association acquisitions are required before candidate vetting'
      using errcode='55000';
  end if;
  perform community_orgs.save_registry_seed_triage_before_three_source_gate(
    p_version,p_revision,p_decision,p_target_candidate,p_target_record,p_note);
end $$;
revoke all on function
  community_orgs.save_registry_seed_triage_before_three_source_gate(text,integer,text,text,text,text),
  community_orgs.save_registry_seed_triage(text,integer,text,text,text,text)
  from public,anon,service_role,ingestion_worker;
grant execute on function community_orgs.save_registry_seed_triage(text,integer,text,text,text,text)
  to authenticated;

alter function community_orgs.promote_registry_seed_candidates(text,text[],text)
  rename to promote_registry_seed_candidates_before_three_source_gate;
create function community_orgs.promote_registry_seed_candidates(
  p_release text,p_versions text[],p_reason text
) returns text language plpgsql security definer set search_path='' as $$
begin
  if community_orgs.registry_seed_vetting_readiness()->>'ready' <> 'true' then
    raise exception 'Complete ABR, ACNC and NSW association acquisitions are required before candidate promotion'
      using errcode='55000';
  end if;
  return community_orgs.promote_registry_seed_candidates_before_three_source_gate(
    p_release,p_versions,p_reason);
end $$;
revoke all on function
  community_orgs.promote_registry_seed_candidates_before_three_source_gate(text,text[],text),
  community_orgs.promote_registry_seed_candidates(text,text[],text)
  from public,anon,service_role,ingestion_worker;
grant execute on function community_orgs.promote_registry_seed_candidates(text,text[],text)
  to authenticated;

comment on view ingestion.registry_seed_cross_source_matches is
  'Private ABR-to-ACNC/NSW suggestions; names remain weak evidence and never auto-link.';
comment on function community_orgs.registry_seed_vetting_readiness() is
  'Three-source acquisition gate for ABR candidate vetting.';
comment on function community_orgs.registry_seed_triage_queue(
  text,text,text,integer,text,text,text,text,text
) is 'ABR candidate queue bounded by community entity type or genuine ACNC/NSW evidence.';

commit;
