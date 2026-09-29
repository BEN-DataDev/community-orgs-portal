-- Set-based, resumable publication of the complete retained seed union. Exact ABN
-- and verified NSW incorporation identifiers deduplicate records; names never do.
begin;

create table ingestion.full_seed_publications (
  publication_id uuid primary key default gen_random_uuid(),
  abr_release_id bigint not null references ingestion.registry_seed_releases(id),
  acnc_run_id bigint not null references ingestion.ingestion_runs(id),
  nsw_release_id bigint not null references ingestion.registry_seed_releases(id),
  status text not null default 'preparing' check(status in ('preparing','prepared','publishing','published')),
  source_row_count bigint,
  canonical_count bigint,
  selection_sha256 text check(selection_sha256 is null or selection_sha256 ~ '^[0-9a-f]{64}$'),
  reason text not null check(length(btrim(reason)) between 1 and 2000),
  prepared_by uuid not null references auth.users(id),
  prepared_at timestamptz not null default now(),
  published_at timestamptz,
  unique(abr_release_id, acnc_run_id, nsw_release_id)
);

create table ingestion.full_seed_items (
  publication_id uuid not null references ingestion.full_seed_publications(publication_id) on delete restrict,
  canonical_key text not null,
  organisation_id uuid not null,
  existing_organisation boolean not null,
  entity_name text not null,
  abn text,
  entity_type text,
  incorporation_number text,
  incorporation_status boolean,
  incorporation_registration_date date,
  website text,
  source_refs jsonb not null check(jsonb_typeof(source_refs)='object'),
  applied_at timestamptz,
  primary key(publication_id, canonical_key),
  unique(publication_id, organisation_id),
  check(abn is null or abn ~ '^[0-9]{11}$')
);

create index full_seed_items_pending_idx on ingestion.full_seed_items(publication_id, canonical_key) where applied_at is null;
alter table ingestion.full_seed_publications enable row level security;
alter table ingestion.full_seed_items enable row level security;
revoke all on ingestion.full_seed_publications, ingestion.full_seed_items from public,anon,authenticated,service_role,ingestion_worker;

create or replace function community_orgs.grant_owner_on_organisation_insert()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_owner_role_id uuid;
begin
 if auth.uid() is null
    or exists(select 1 from ingestion.creation_targets where org_id=NEW.org_id)
    or exists(select 1 from ingestion.full_seed_items where organisation_id=NEW.org_id)
 then return NEW; end if;
 select id into v_owner_role_id from community_orgs.roles where name='owner' limit 1;
 if v_owner_role_id is null then return NEW; end if;
 insert into community_orgs.user_organisation_roles(user_id,organisation_id,role_id,granted_by,is_active)
 values(auth.uid(),NEW.org_id,v_owner_role_id,auth.uid(),true) on conflict do nothing;
 return NEW;
end $$;

create function community_orgs.prepare_full_seed_union(p_reason text)
returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; source_rows bigint; canonical_rows bigint; selection_hash text;
begin
  if community_orgs.is_data_steward() is distinct from true then
    raise exception 'Data Steward required' using errcode='42501';
  end if;
  if nullif(btrim(p_reason),'') is null or length(p_reason)>2000 then
    raise exception 'A preparation reason is required' using errcode='22023';
  end if;
  if not exists(select 1 from ingestion.registry_seed_releases where id=2 and source_id='abr-bulk' and completion='complete' and raw_removed_at is null)
     or not exists(select 1 from ingestion.ingestion_runs where id=34 and source_id='acnc-register' and completion='complete' and raw_removed_at is null)
     or not exists(select 1 from ingestion.registry_seed_releases where id=3 and source_id='nsw-incorporated-associations' and completion='complete' and raw_removed_at is null) then
    raise exception 'Complete retained ABR 2, ACNC 34 and NSW 3 artifacts are required' using errcode='55000';
  end if;
  select publication_id into result from ingestion.full_seed_publications
   where abr_release_id=2 and acnc_run_id=34 and nsw_release_id=3;
  if found then return result; end if;
  insert into ingestion.full_seed_publications(abr_release_id,acnc_run_id,nsw_release_id,reason,prepared_by)
  values(2,34,3,btrim(p_reason),auth.uid()) returning publication_id into result;

  with abr as materialized (
    select cv.id version_id,
      (select a->'value'#>>'{}' from jsonb_array_elements(cv.payload->'assertions') a where a->>'field'='abn') abn,
      (select a->'value'#>>'{}' from jsonb_array_elements(cv.payload->'assertions') a where a->>'field'='entity_name') entity_name,
      (select a->'value'#>>'{}' from jsonb_array_elements(cv.payload->'assertions') a where a->>'field'='abr_entity_type') entity_type
    from ingestion.registry_seed_release_candidates rc join ingestion.registry_seed_candidate_versions cv on cv.id=rc.version_id
    where rc.release_id=2 and rc.in_scope
  ), acnc as materialized (
    select v.id version_id,
      (select a->'value'#>>'{}' from jsonb_array_elements(v.payload->'assertions') a where a->>'field'='abn') abn,
      (select a->'value'#>>'{}' from jsonb_array_elements(v.payload->'assertions') a where a->>'field'='entity_name') entity_name,
      (select a->'value'#>>'{}' from jsonb_array_elements(v.payload->'assertions') a where a->>'field'='website') website
    from ingestion.run_records rr join ingestion.source_record_versions v on v.id=rr.version_id where rr.run_id=34
  ), abn_union as (
    select coalesce(a.abn,c.abn) abn,coalesce(c.entity_name,a.entity_name) entity_name,a.entity_type,c.website,
      a.version_id abr_version_id,c.version_id acnc_version_id
    from abr a full join acnc c using(abn)
  ), abn_existing as (
    select u.*,coalesce(l.org_id,k.holder) existing_org
    from abn_union u
    left join lateral (select org_id from community_orgs.legal_details where regexp_replace(abn,'[^0-9]','','g')=u.abn order by org_id limit 1) l on true
    left join lateral (select holder from ingestion.identifier_keys where scheme='abn' and jurisdiction='AU' and normalized_value=u.abn and state='verified' order by id limit 1) k on true
  ), nsw as materialized (
    select cv.id version_id,c.native_id,
      (select a->'value'#>>'{}' from jsonb_array_elements(cv.payload->'assertions') a where a->>'field'='entity_name') entity_name,
      (select a->'value'#>>'{}' from jsonb_array_elements(cv.payload->'assertions') a where a->>'field'='csv_incorporation_number') incorporation_number,
      (select a->'value'#>>'{}' from jsonb_array_elements(cv.payload->'assertions') a where a->>'field'='nsw_association_type') entity_type,
      (select a->'value'#>>'{}' from jsonb_array_elements(cv.payload->'assertions') a where a->>'field'='nsw_date_registered') registration_date
    from ingestion.registry_seed_release_candidates rc join ingestion.registry_seed_candidate_versions cv on cv.id=rc.version_id
    join ingestion.registry_seed_candidates c on c.id=cv.candidate_id where rc.release_id=3 and rc.in_scope
  ), nsw_existing as (
    select n.*,k.holder existing_org from nsw n left join lateral (
      select holder from ingestion.identifier_keys where scheme='incorporated_association' and jurisdiction='AU-NSW'
       and normalized_value=n.incorporation_number and state='verified' order by id limit 1
    ) k on true
  ), selected as (
    select 'abn:'||abn canonical_key,coalesce(existing_org,gen_random_uuid()) org_id,existing_org is not null existing_org,
      entity_name,abn,entity_type,null::text incorporation_number,null::date registration_date,website,
      jsonb_strip_nulls(jsonb_build_object('abr_release_id',2,'abr_version_id',abr_version_id,'acnc_run_id',34,'acnc_version_id',acnc_version_id)) source_refs
    from abn_existing
    union all
    select 'incorporated_association:AU-NSW:'||incorporation_number,coalesce(existing_org,gen_random_uuid()),existing_org is not null,
      entity_name,null,entity_type,incorporation_number,
      case when registration_date ~ '^\\d{4}-\\d{2}-\\d{2}$' then registration_date::date end,null,
      jsonb_build_object('nsw_release_id',3,'nsw_version_id',version_id,'nsw_native_id',native_id)
    from nsw_existing
  )
  insert into ingestion.full_seed_items(publication_id,canonical_key,organisation_id,existing_organisation,entity_name,abn,entity_type,
    incorporation_number,incorporation_status,incorporation_registration_date,website,source_refs)
  select result,canonical_key,org_id,existing_org,entity_name,abn,entity_type,incorporation_number,
    case when incorporation_number is not null then true end,registration_date,website,source_refs from selected;

  select count(*) into source_rows from ingestion.registry_seed_release_candidates where release_id in (2,3) and in_scope;
  source_rows:=source_rows+(select count(*) from ingestion.run_records where run_id=34);
  select count(*),encode(sha256(convert_to(string_agg(canonical_key||':'||organisation_id::text,',' order by canonical_key),'UTF8')),'hex')
    into canonical_rows,selection_hash from ingestion.full_seed_items where publication_id=result;
  update ingestion.full_seed_publications set status='prepared',source_row_count=source_rows,
    canonical_count=canonical_rows,selection_sha256=selection_hash where publication_id=result;
  return result;
end $$;

create function community_orgs.apply_full_seed_union_batch(p_publication uuid,p_limit integer default 1000)
returns jsonb language plpgsql security definer set search_path='' as $$
declare publication ingestion.full_seed_publications; applied bigint; pending bigint;
begin
  if community_orgs.is_data_steward() is distinct from true then raise exception 'Data Steward required' using errcode='42501'; end if;
  if p_limit not between 1 and 5000 then raise exception 'Batch size must be between 1 and 5000' using errcode='22023'; end if;
  select * into publication from ingestion.full_seed_publications where publication_id=p_publication for update;
  if not found then raise exception 'Full seed publication not found' using errcode='P0002'; end if;
  if publication.status='published' then return jsonb_build_object('publication_id',p_publication,'status','published','applied',0,'pending',0); end if;
  if publication.status not in ('prepared','publishing') then raise exception 'Full seed union is not prepared' using errcode='55000'; end if;
  update ingestion.full_seed_publications set status='publishing' where publication_id=p_publication;

  with batch as materialized (select * from ingestion.full_seed_items where publication_id=p_publication and applied_at is null order by canonical_key limit p_limit)
  insert into community_orgs.organisations(org_id,entity_name,slug,is_public,inserted_by,last_edited_by)
  select organisation_id,entity_name,'seed-'||md5(canonical_key),true,auth.uid(),auth.uid() from batch b
  where not exists(select 1 from community_orgs.organisations o where o.org_id=b.organisation_id);

  with batch as materialized (select * from ingestion.full_seed_items where publication_id=p_publication and applied_at is null order by canonical_key limit p_limit)
  insert into community_orgs.legal_details(org_id,abn,entity_type,incorporation_number,incorporation_status,incorporation_registration_date,inserted_by,last_edited_by)
  select organisation_id,abn,entity_type,incorporation_number,incorporation_status,incorporation_registration_date,auth.uid(),auth.uid()
  from batch b where not exists(select 1 from community_orgs.legal_details l where l.org_id=b.organisation_id)
    and (abn is not null or incorporation_number is not null);

  with batch as materialized (select * from ingestion.full_seed_items where publication_id=p_publication and applied_at is null order by canonical_key limit p_limit)
  insert into community_orgs.contact_info(org_id,website,inserted_by,last_edited_by)
  select organisation_id,website,auth.uid(),auth.uid() from batch b
  where website is not null and website ~ '^https?://' and not exists(select 1 from community_orgs.contact_info c where c.org_id=b.organisation_id);

  with batch as materialized (select * from ingestion.full_seed_items where publication_id=p_publication and applied_at is null order by canonical_key limit p_limit)
  insert into ingestion.identifier_keys(scheme,jurisdiction,normalized_value,holder,state,evidence,reviewed_by)
  select case when abn is not null then 'abn' else 'incorporated_association' end,
    case when abn is not null then 'AU' else 'AU-NSW' end,coalesce(abn,incorporation_number),organisation_id,'verified',
    jsonb_build_object('full_seed_publication_id',p_publication,'sources',source_refs),auth.uid()
  from batch where coalesce(abn,incorporation_number) is not null
  on conflict(scheme,jurisdiction,normalized_value) do nothing;

  with batch as materialized (select * from ingestion.full_seed_items where publication_id=p_publication and applied_at is null order by canonical_key limit p_limit),
  links as (select (b.source_refs->>'acnc_version_id')::bigint version_id,b.organisation_id from batch b where b.source_refs ? 'acnc_version_id')
  insert into ingestion.source_links(record_id,organisation_id)
  select v.record_id,l.organisation_id from links l join ingestion.source_record_versions v on v.id=l.version_id
  on conflict(record_id) do nothing;

  with batch as materialized (select * from ingestion.full_seed_items where publication_id=p_publication and applied_at is null order by canonical_key limit p_limit),
  imported_fields as (
    select organisation_id,'organisations'::text table_name,'entity_name'::text field from batch where not existing_organisation
    union all select organisation_id,'legal_details','abn' from batch where not existing_organisation and abn is not null
    union all select organisation_id,'contact_info','website' from batch where not existing_organisation and website is not null
  )
  update ingestion.field_state state set protected=false
  from imported_fields f where state.org_id=f.organisation_id and state.table_name=f.table_name and state.field=f.field;

  with batch as materialized (select canonical_key from ingestion.full_seed_items where publication_id=p_publication and applied_at is null order by canonical_key limit p_limit)
  update ingestion.full_seed_items item set applied_at=clock_timestamp() from batch
  where item.publication_id=p_publication and item.canonical_key=batch.canonical_key;
  get diagnostics applied=row_count;
  select count(*) into pending from ingestion.full_seed_items where publication_id=p_publication and applied_at is null;
  if pending=0 then update ingestion.full_seed_publications set status='published',published_at=clock_timestamp() where publication_id=p_publication; end if;
  return jsonb_build_object('publication_id',p_publication,'status',case when pending=0 then 'published' else 'publishing' end,'applied',applied,'pending',pending);
end $$;

create function community_orgs.full_seed_union_status(p_publication uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p ingestion.full_seed_publications;
begin
 if community_orgs.is_data_steward() is distinct from true then raise exception 'Data Steward required' using errcode='42501'; end if;
 select * into p from ingestion.full_seed_publications where publication_id=p_publication;
 if not found then raise exception 'Full seed publication not found' using errcode='P0002'; end if;
 return jsonb_build_object('publication_id',p.publication_id,'status',p.status,'source_row_count',p.source_row_count,
  'canonical_count',p.canonical_count,'selection_sha256',p.selection_sha256,'applied',(select count(*) from ingestion.full_seed_items where publication_id=p.publication_id and applied_at is not null),
  'pending',(select count(*) from ingestion.full_seed_items where publication_id=p.publication_id and applied_at is null),'prepared_at',p.prepared_at,'published_at',p.published_at);
end $$;

revoke all on function community_orgs.prepare_full_seed_union(text),community_orgs.apply_full_seed_union_batch(uuid,integer),community_orgs.full_seed_union_status(uuid)
 from public,anon,service_role,ingestion_worker;
grant execute on function community_orgs.prepare_full_seed_union(text),community_orgs.apply_full_seed_union_batch(uuid,integer),community_orgs.full_seed_union_status(uuid)
 to authenticated;

commit;
