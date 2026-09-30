-- Correct the over-broad full seed without rewriting its immutable publication
-- evidence. Retain ABR OIE/UIE and every ACNC record. NSW associations merge to
-- a retained ABN entity on a unique normalised name or a high-confidence unique
-- trigram match; otherwise they remain distinct.
begin;

create table ingestion.seed_publication_corrections (
  correction_id uuid primary key default gen_random_uuid(),
  publication_id uuid not null references ingestion.full_seed_publications(publication_id),
  rule_version text not null,
  status text not null default 'preparing'
    check (status in ('preparing','prepared','applying','applied')),
  similarity_threshold numeric not null,
  similarity_margin numeric not null,
  source_count bigint,
  keep_count bigint,
  merge_count bigint,
  remove_count bigint,
  reason text not null,
  prepared_at timestamptz not null default now(),
  applied_at timestamptz,
  unique(publication_id, rule_version)
);

create table ingestion.seed_publication_correction_items (
  correction_id uuid not null
    references ingestion.seed_publication_corrections(correction_id) on delete restrict,
  source_organisation_id uuid not null,
  action text not null check(action in ('keep','merge','remove')),
  target_organisation_id uuid,
  match_method text,
  similarity_score numeric,
  second_similarity_score numeric,
  source_name text not null,
  target_name text,
  reason text not null,
  applied_at timestamptz,
  primary key(correction_id, source_organisation_id),
  check ((action='merge')=(target_organisation_id is not null)),
  check (action<>'merge' or source_organisation_id<>target_organisation_id)
);

create index seed_publication_correction_pending_idx
  on ingestion.seed_publication_correction_items(correction_id, action, source_organisation_id)
  where applied_at is null;

alter table ingestion.seed_publication_corrections enable row level security;
alter table ingestion.seed_publication_correction_items enable row level security;
revoke all on ingestion.seed_publication_corrections,
  ingestion.seed_publication_correction_items
  from public, anon, authenticated, service_role, ingestion_worker;

create function ingestion.prepare_seed_publication_correction(
  p_publication uuid,
  p_reason text,
  p_similarity_threshold numeric default 0.90,
  p_similarity_margin numeric default 0.10
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  result uuid;
  publication ingestion.full_seed_publications;
begin
  if nullif(btrim(p_reason),'') is null then
    raise exception 'A correction reason is required' using errcode='22023';
  end if;
  if p_similarity_threshold not between 0.5 and 1
     or p_similarity_margin not between 0 and 0.5 then
    raise exception 'Invalid name-similarity boundary' using errcode='22023';
  end if;
  select * into publication from ingestion.full_seed_publications
    where publication_id=p_publication and status='published';
  if not found then raise exception 'Published full-seed publication required' using errcode='55000'; end if;

  select correction_id into result from ingestion.seed_publication_corrections
    where publication_id=p_publication and rule_version='community-entities-v1';
  if found then
    return (select jsonb_build_object(
      'correction_id',c.correction_id,'status',c.status,'source_count',c.source_count,
      'keep',c.keep_count,'merge',c.merge_count,'remove',c.remove_count)
      from ingestion.seed_publication_corrections c where c.correction_id=result);
  end if;

  insert into ingestion.seed_publication_corrections(
    publication_id,rule_version,similarity_threshold,similarity_margin,reason
  ) values (
    p_publication,'community-entities-v1',p_similarity_threshold,p_similarity_margin,btrim(p_reason)
  ) returning correction_id into result;

  create temporary table correction_items_normalised on commit drop as
  select i.*,
    case when i.entity_type ~ '^\s*\{'
      then jsonb_extract_path_text(i.entity_type::jsonb,'code') end abr_code,
    regexp_replace(
      regexp_replace(lower(replace(i.entity_name,'&',' and ')),'[^a-z0-9]+',' ','g'),
      '(^ +| +$)','', 'g'
    ) name_norm,
    regexp_replace(lower(replace(i.entity_name,'&',' and ')),'[^a-z0-9]+','','g') name_key
  from ingestion.full_seed_items i where i.publication_id=p_publication;

  create temporary table correction_canonical on commit drop as
  select * from correction_items_normalised
  where abn is not null and (
    abr_code in ('OIE','UIE') or source_refs ? 'acnc_version_id'
  );

  create temporary table correction_nsw on commit drop as
  select * from correction_items_normalised where source_refs ? 'nsw_version_id';

  create temporary table correction_matches (
    source_organisation_id uuid primary key,
    target_organisation_id uuid not null,
    match_method text not null,
    score numeric not null,
    second_score numeric,
    target_name text not null
  ) on commit drop;

  with candidates as (
    select n.organisation_id source_id,c.organisation_id target_id,c.entity_name,
      count(*) over(partition by n.organisation_id) candidate_count
    from correction_nsw n join correction_canonical c using(name_key)
    where length(n.name_key)>=5
  )
  insert into correction_matches
  select source_id,target_id,'unique_normalised_name',1,null,entity_name
  from candidates where candidate_count=1;

  with unmatched as materialized (
    select n.* from correction_nsw n
    where not exists(select 1 from correction_canonical c
      where c.name_key=n.name_key and length(n.name_key)>=5)
  ), ranked as (
    select n.organisation_id source_id,choice.target_id,choice.entity_name,
      choice.score,choice.rank
    from unmatched n
    cross join lateral (
      select c.organisation_id target_id,c.entity_name,
        extensions.similarity(n.name_norm,c.name_norm)::numeric score,
        row_number() over(order by extensions.similarity(n.name_norm,c.name_norm) desc,c.organisation_id) rank
      from correction_canonical c
      order by score desc,c.organisation_id limit 2
    ) choice
  ), best as (
    select source_id,
      max(target_id::text) filter(where rank=1)::uuid target_id,
      max(entity_name) filter(where rank=1) target_name,
      max(score) filter(where rank=1) score,
      max(score) filter(where rank=2) second_score
    from ranked group by source_id
  )
  insert into correction_matches
  select source_id,target_id,'trigram_name_similarity',score,second_score,target_name
  from best where score>=p_similarity_threshold
    and score-coalesce(second_score,0)>=p_similarity_margin;

  insert into ingestion.seed_publication_correction_items(
    correction_id,source_organisation_id,action,target_organisation_id,
    match_method,similarity_score,second_similarity_score,
    source_name,target_name,reason
  )
  select result,n.organisation_id,'merge',m.target_organisation_id,
    m.match_method,m.score,m.second_score,n.entity_name,m.target_name,
    case m.match_method
      when 'unique_normalised_name' then 'NSW association uniquely matches a retained ABN entity after name normalisation'
      else 'NSW association has a high-confidence unique name-similarity match to a retained ABN entity'
    end
  from correction_nsw n join correction_matches m
    on m.source_organisation_id=n.organisation_id
  union all
  select result,c.organisation_id,'keep',null,null,null,null,c.entity_name,null,
    case when c.source_refs ? 'acnc_version_id'
      then 'Retain qualified ACNC evidence and exact ABN identity'
      else 'Retain ABR Other Incorporated/Unincorporated Entity' end
  from correction_canonical c
  union all
  select result,n.organisation_id,'keep',null,null,null,null,n.entity_name,null,
    'Retain unmatched or ambiguous NSW incorporated association as a distinct organisation'
  from correction_nsw n where not exists(
    select 1 from correction_matches m where m.source_organisation_id=n.organisation_id
  )
  union all
  select result,i.organisation_id,'remove',null,null,null,null,i.entity_name,null,
    'Outside authorised seed scope: neither OIE/UIE nor qualified ACNC/NSW evidence'
  from correction_items_normalised i
  where not exists(select 1 from correction_canonical c where c.organisation_id=i.organisation_id)
    and not exists(select 1 from correction_nsw n where n.organisation_id=i.organisation_id);

  if (select count(*) from ingestion.seed_publication_correction_items
      where correction_id=result)<>publication.canonical_count then
    raise exception 'Correction inventory does not cover the immutable publication' using errcode='55000';
  end if;
  if exists(
    select 1 from ingestion.seed_publication_correction_items ci
    join ingestion.full_seed_items i on i.publication_id=p_publication
      and i.organisation_id=ci.source_organisation_id
    where ci.correction_id=result and ci.action in ('merge','remove')
      and i.existing_organisation
  ) then
    raise exception 'Correction would remove an organisation that predated the publication' using errcode='55000';
  end if;
  if exists(
    select 1 from ingestion.seed_publication_correction_items ci
    join community_orgs.organisations o on o.org_id=ci.source_organisation_id
    where ci.correction_id=result and ci.action in ('merge','remove')
      and o.last_edited_at>publication.published_at::timestamp
  ) then
    raise exception 'A correction target was edited after publication' using errcode='55000';
  end if;

  update ingestion.seed_publication_corrections c set
    status='prepared',
    source_count=(select count(*) from ingestion.seed_publication_correction_items where correction_id=result),
    keep_count=(select count(*) from ingestion.seed_publication_correction_items where correction_id=result and action='keep'),
    merge_count=(select count(*) from ingestion.seed_publication_correction_items where correction_id=result and action='merge'),
    remove_count=(select count(*) from ingestion.seed_publication_correction_items where correction_id=result and action='remove')
  where c.correction_id=result;

  return (select jsonb_build_object(
    'correction_id',c.correction_id,'status',c.status,'source_count',c.source_count,
    'keep',c.keep_count,'merge',c.merge_count,'remove',c.remove_count)
    from ingestion.seed_publication_corrections c where c.correction_id=result);
end $$;

create function ingestion.apply_seed_publication_correction_batch(
  p_correction uuid,p_limit integer default 2000
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  correction ingestion.seed_publication_corrections;
  publication ingestion.full_seed_publications;
  fact record;
  dependency record;
  unexpected boolean;
  applied bigint;
  pending bigint;
begin
  if p_limit not between 1 and 5000 then raise exception 'Invalid batch size' using errcode='22023'; end if;
  select * into correction from ingestion.seed_publication_corrections
    where correction_id=p_correction for update;
  if not found then raise exception 'Seed correction not found' using errcode='P0002'; end if;
  if correction.status='applied' then
    return jsonb_build_object('correction_id',p_correction,'status','applied','applied',0,'pending',0);
  end if;
  if correction.status not in ('prepared','applying') then
    raise exception 'Seed correction is not prepared' using errcode='55000';
  end if;
  select * into publication from ingestion.full_seed_publications
    where publication_id=correction.publication_id;
  update ingestion.seed_publication_corrections set status='applying'
    where correction_id=p_correction;

  create temporary table correction_batch on commit drop as
  select * from ingestion.seed_publication_correction_items
  where correction_id=p_correction and applied_at is null
  order by case action when 'keep' then 0 when 'merge' then 1 else 2 end,
    source_organisation_id limit p_limit;

  if exists(
    select 1 from correction_batch b
    left join community_orgs.organisations o on o.org_id=b.source_organisation_id
    where o.org_id is null
  ) then raise exception 'Correction source organisation is missing' using errcode='55000'; end if;
  if exists(
    select 1 from correction_batch b
    join community_orgs.organisations o on o.org_id=b.source_organisation_id
    where b.action in ('merge','remove')
      and o.last_edited_at>publication.published_at::timestamp
  ) then raise exception 'Correction target was edited after publication' using errcode='55000'; end if;

  -- Abort rather than erase any later relationship, review, publication or user data.
  for dependency in
    select ns.nspname schema_name,cl.relname table_name,att.attname column_name
    from pg_catalog.pg_constraint con
    join pg_catalog.pg_class cl on cl.oid=con.conrelid
    join pg_catalog.pg_namespace ns on ns.oid=cl.relnamespace
    join pg_catalog.pg_attribute att on att.attrelid=con.conrelid and att.attnum=con.conkey[1]
    where con.contype='f' and con.confrelid='community_orgs.organisations'::regclass
      and con.confdeltype in ('a','r') and cardinality(con.conkey)=1
      and not (ns.nspname='community_orgs' and cl.relname in ('legal_details','contact_info'))
      and not (ns.nspname='ingestion' and cl.relname='identifier_keys')
  loop
    execute format(
      'select exists(select 1 from %I.%I d join pg_temp.correction_batch b on d.%I=b.source_organisation_id where b.action in (''merge'',''remove''))',
      dependency.schema_name,dependency.table_name,dependency.column_name
    ) into unexpected;
    if unexpected then
      raise exception 'Correction target has dependent data in %.%',dependency.schema_name,dependency.table_name
        using errcode='55000';
    end if;
  end loop;

  if exists(
    select 1 from correction_batch b join community_orgs.legal_details l
      on l.org_id=b.source_organisation_id
    where b.action in ('merge','remove') and l.last_edited_at>publication.published_at::timestamp
  ) or exists(
    select 1 from correction_batch b join community_orgs.contact_info c
      on c.org_id=b.source_organisation_id
    where b.action in ('merge','remove') and c.last_edited_at>publication.published_at::timestamp
  ) then raise exception 'Correction target has later child-table edits' using errcode='55000'; end if;

  -- Correct the ABR JSON display value on retained organisations.
  update community_orgs.legal_details l set
    entity_type=jsonb_extract_path_text(i.entity_type::jsonb,'text')
  from correction_batch b
  join ingestion.full_seed_items i on i.publication_id=correction.publication_id
    and i.organisation_id=b.source_organisation_id
  where b.action='keep' and i.entity_type ~ '^\s*\{'
    and l.org_id=b.source_organisation_id;

  -- Publish every valid mapped ACNC run-34 fact into its existing merged target.
  if exists(
    select 1 from correction_batch b
    join ingestion.full_seed_items i on i.publication_id=correction.publication_id
      and i.organisation_id=b.source_organisation_id
    join ingestion.source_record_versions sv
      on sv.id=(i.source_refs->>'acnc_version_id')::bigint
    join ingestion.source_links link on link.record_id=sv.record_id
    where b.action='keep' and i.source_refs ? 'acnc_version_id'
      and link.organisation_id is distinct from b.source_organisation_id
  ) then raise exception 'ACNC source record is linked to a different organisation' using errcode='55000'; end if;
  insert into ingestion.source_links(record_id,organisation_id)
  select sv.record_id,b.source_organisation_id
  from correction_batch b
  join ingestion.full_seed_items i on i.publication_id=correction.publication_id
    and i.organisation_id=b.source_organisation_id
  join ingestion.source_record_versions sv
    on sv.id=(i.source_refs->>'acnc_version_id')::bigint
  where b.action='keep' and i.source_refs ? 'acnc_version_id'
  on conflict(record_id) do nothing;
  for fact in
    select b.source_organisation_id org_id,sv.record_id,a.field,a.value,m.table_name
    from correction_batch b
    join ingestion.full_seed_items i on i.publication_id=correction.publication_id
      and i.organisation_id=b.source_organisation_id
    join ingestion.source_record_versions sv
      on sv.id=(i.source_refs->>'acnc_version_id')::bigint
    join ingestion.field_assertions a on a.version_id=sv.id
    join ingestion.field_mappings m on m.field=a.field
    where b.action='keep' and i.source_refs ? 'acnc_version_id'
      and ingestion.valid_field_value(m,a.value)
    order by b.source_organisation_id,a.field
  loop
    perform ingestion.write_field(fact.org_id,fact.record_id,fact.field,fact.value);
    update ingestion.field_state set protected=false
      where org_id=fact.org_id and table_name=fact.table_name and field=fact.field
        and record_id=case when fact.table_name='acnc_register_details' then fact.record_id else 0 end;
  end loop;
  update community_orgs.acnc_register_details d set is_public=true
  from correction_batch b where b.action='keep' and d.org_id=b.source_organisation_id;

  if exists(
    select 1 from correction_batch b
    join ingestion.full_seed_items source on source.publication_id=correction.publication_id
      and source.organisation_id=b.source_organisation_id
    join community_orgs.legal_details target on target.org_id=b.target_organisation_id
    where b.action='merge' and target.incorporation_number is not null
      and target.incorporation_number is distinct from source.incorporation_number
  ) then raise exception 'NSW merge conflicts with an existing incorporation number' using errcode='55000'; end if;

  update community_orgs.legal_details target set
    incorporation_number=source.incorporation_number,
    incorporation_status=source.incorporation_status,
    incorporation_registration_date=source.incorporation_registration_date
  from correction_batch b
  join ingestion.full_seed_items source on source.publication_id=correction.publication_id
    and source.organisation_id=b.source_organisation_id
  where b.action='merge' and target.org_id=b.target_organisation_id
    and target.legal_id=(select l.legal_id from community_orgs.legal_details l
      where l.org_id=b.target_organisation_id order by l.legal_id limit 1);

  insert into community_orgs.aliases(org_id,alias,alias_type)
  select b.target_organisation_id,b.source_name,null
  from correction_batch b
  join community_orgs.organisations target on target.org_id=b.target_organisation_id
  where b.action='merge'
    and regexp_replace(lower(b.source_name),'[^a-z0-9]+','','g')
      <>regexp_replace(lower(target.entity_name),'[^a-z0-9]+','','g')
    and not exists(select 1 from community_orgs.aliases a
      where a.org_id=b.target_organisation_id and lower(a.alias)=lower(b.source_name));

  update ingestion.identifier_keys k set
    holder=b.target_organisation_id,
    evidence=k.evidence||jsonb_build_object(
      'seed_scope_correction_id',p_correction,
      'name_match_method',b.match_method,
      'name_similarity_score',b.similarity_score
    ),
    revision=k.revision+1,
    reviewed_at=clock_timestamp()
  from correction_batch b
  where b.action='merge' and k.holder=b.source_organisation_id
    and k.scheme='incorporated_association' and k.jurisdiction='AU-NSW';

  delete from ingestion.identifier_keys k using correction_batch b
    where b.action='remove' and k.holder=b.source_organisation_id;
  delete from community_orgs.contact_info c using correction_batch b
    where b.action in ('merge','remove') and c.org_id=b.source_organisation_id;
  delete from community_orgs.legal_details l using correction_batch b
    where b.action in ('merge','remove') and l.org_id=b.source_organisation_id;
  delete from community_orgs.organisations o using correction_batch b
    where b.action in ('merge','remove') and o.org_id=b.source_organisation_id;

  update ingestion.seed_publication_correction_items item set applied_at=clock_timestamp()
  from correction_batch b where item.correction_id=p_correction
    and item.source_organisation_id=b.source_organisation_id;
  get diagnostics applied=row_count;
  select count(*) into pending from ingestion.seed_publication_correction_items
    where correction_id=p_correction and applied_at is null;
  if pending=0 then
    update ingestion.seed_publication_corrections
      set status='applied',applied_at=clock_timestamp() where correction_id=p_correction;
  end if;
  return jsonb_build_object('correction_id',p_correction,
    'status',case when pending=0 then 'applied' else 'applying' end,
    'applied',applied,'pending',pending);
end $$;

revoke all on function ingestion.prepare_seed_publication_correction(uuid,text,numeric,numeric),
  ingestion.apply_seed_publication_correction_batch(uuid,integer)
  from public,anon,authenticated,service_role,ingestion_worker;

commit;
