-- Human review of the name-based NSW merges made by the seed scope correction
-- (correction rule community-entities-v1). Names are never identity keys, so each
-- merge is confirmed or split by a Data Steward. One steward decides; there is no
-- second approval (initial-seed policy: one person may prepare and approve).
--
-- Confirm: the moved NSW identifier key records the review.
-- Split:   the NSW association is restored under its original organisation id
--          from the immutable full-seed item, its key moves back to it, and the
--          retained ABN entity gets back its own full-seed incorporation values
--          and loses the alias the merge added.
begin;

create table ingestion.seed_merge_reviews (
  correction_id uuid not null,
  source_organisation_id uuid not null,
  decision text not null check (decision in ('confirmed', 'split')),
  note text check (note is null or length(btrim(note)) between 1 and 2000),
  reviewed_by uuid not null references auth.users,
  reviewed_at timestamptz not null default now(),
  primary key (correction_id, source_organisation_id),
  foreign key (correction_id, source_organisation_id)
    references ingestion.seed_publication_correction_items on delete restrict,
  check (decision <> 'split' or note is not null)
);

alter table ingestion.seed_merge_reviews enable row level security;
revoke all on ingestion.seed_merge_reviews
  from public, anon, authenticated, service_role, ingestion_worker;

-- Organisations restored from a full-seed item are imports, not self-registered:
-- start them unclaimed, as grant_owner_on_organisation_insert already assumes.
create or replace function community_orgs.initialise_organisation_stewardship()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  initial_state community_orgs.stewardship_state;
  event bigint;
  imported boolean;
begin
  select exists(select 1 from ingestion.creation_targets where org_id = new.org_id)
      or exists(select 1 from ingestion.full_seed_items where organisation_id = new.org_id)
    into imported;
  initial_state := case when auth.uid() is not null and not imported
    then 'self_managed'::community_orgs.stewardship_state
    else 'unclaimed'::community_orgs.stewardship_state end;
  insert into community_orgs.organisation_stewardship_events(
    organisation_id, revision, previous_state, next_state, actor_id, reason,
    approval_reference, note
  ) values (
    new.org_id, 1, null, initial_state,
    case when imported then null else auth.uid() end,
    case when imported then 'Imported publication created an unclaimed organisation'
      when auth.uid() is not null then 'Registered account created the organisation'
      else 'Database operation created an unclaimed organisation' end,
    case when initial_state = 'self_managed' then 'direct-organisation-creation' end,
    case when initial_state = 'self_managed'
      then 'The creator received the owner role in the same transaction.'
      else 'No organisation representative has accepted stewardship.' end
  ) returning event_id into event;
  insert into community_orgs.organisation_stewardship(
    organisation_id, state, revision, current_event_id, updated_at
  ) values (new.org_id, initial_state, 1, event, now());
  return new;
end
$$;

create function community_orgs.seed_merge_review_queue(
  p_status text default 'pending',
  p_method text default null,
  p_offset integer default 0,
  p_limit integer default 25
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if community_orgs.is_data_steward() is distinct from true then
    raise exception 'Data Steward required' using errcode = '42501';
  end if;
  if p_status not in ('pending', 'confirmed', 'split', 'all')
     or (p_method is not null and p_method not in ('unique_normalised_name', 'trigram_name_similarity'))
     or p_offset not between 0 and 100000 or p_limit not between 1 and 100 then
    raise exception 'Invalid merge review filter' using errcode = '22023';
  end if;
  return (
    with merges as materialized (
      select ci.*, c.publication_id, r.decision, r.note, r.reviewed_at
      from ingestion.seed_publication_correction_items ci
      join ingestion.seed_publication_corrections c using (correction_id)
      left join ingestion.seed_merge_reviews r using (correction_id, source_organisation_id)
      where ci.action = 'merge' and c.status = 'applied'
    ), selected as (
      select * from merges m
      where (p_method is null or m.match_method = p_method)
        and case p_status when 'all' then true
          when 'pending' then m.decision is null else m.decision = p_status end
    )
    select jsonb_build_object(
      'counts', (select jsonb_build_object(
        'pending', count(*) filter (where decision is null),
        'confirmed', count(*) filter (where decision = 'confirmed'),
        'split', count(*) filter (where decision = 'split')) from merges),
      'total', (select count(*) from selected),
      'items', coalesce((select jsonb_agg(item order by ord) from (
        select row_number() over (order by
            m.reviewed_at desc nulls first,
            case m.match_method when 'trigram_name_similarity' then 0 else 1 end,
            m.similarity_score, m.source_name, m.source_organisation_id) ord,
          jsonb_build_object(
            'source_organisation_id', m.source_organisation_id,
            'source_name', m.source_name,
            'incorporation_number', s.incorporation_number,
            'registration_date', s.incorporation_registration_date,
            'source_entity_type', s.entity_type,
            'source_website', s.website,
            'target_organisation_id', m.target_organisation_id,
            'target_name', o.entity_name,
            'target_slug', o.slug,
            'target_abn', l.abn,
            'target_entity_type', l.entity_type,
            'match_method', m.match_method,
            'similarity_score', m.similarity_score,
            'second_similarity_score', m.second_similarity_score,
            'decision', m.decision,
            'note', m.note,
            'reviewed_at', m.reviewed_at
          ) item
        from selected m
        join ingestion.full_seed_items s
          on s.publication_id = m.publication_id and s.organisation_id = m.source_organisation_id
        left join community_orgs.organisations o on o.org_id = m.target_organisation_id
        left join lateral (
          select ld.abn, ld.entity_type from community_orgs.legal_details ld
          where ld.org_id = m.target_organisation_id order by ld.legal_id limit 1
        ) l on true
        order by ord offset p_offset limit p_limit
      ) page), '[]'::jsonb)
    )
  );
end
$$;

create function community_orgs.review_seed_merge(
  p_source uuid,
  p_decision text,
  p_note text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  item ingestion.seed_publication_correction_items;
  source ingestion.full_seed_items;
  target ingestion.full_seed_items;
  k ingestion.identifier_keys;
  note text := nullif(btrim(p_note), '');
  review jsonb;
begin
  if community_orgs.is_data_steward() is distinct from true then
    raise exception 'Data Steward required' using errcode = '42501';
  end if;
  if p_decision not in ('confirmed', 'split')
     or (p_decision = 'split' and note is null) or length(note) > 2000 then
    raise exception 'A decision is required, with a note for a split' using errcode = '22023';
  end if;

  select ci.* into item
  from ingestion.seed_publication_correction_items ci
  join ingestion.seed_publication_corrections c using (correction_id)
  where ci.source_organisation_id = p_source and ci.action = 'merge' and c.status = 'applied'
  for update of ci;
  if not found then raise exception 'Merge not found' using errcode = 'P0002'; end if;
  if exists (select 1 from ingestion.seed_merge_reviews r
    where r.correction_id = item.correction_id and r.source_organisation_id = p_source) then
    raise exception 'Merge already reviewed; reload' using errcode = '40001';
  end if;

  select s.* into source from ingestion.full_seed_items s
  join ingestion.seed_publication_corrections c on c.publication_id = s.publication_id
  where c.correction_id = item.correction_id and s.organisation_id = p_source;
  select s.* into target from ingestion.full_seed_items s
  where s.publication_id = source.publication_id and s.organisation_id = item.target_organisation_id;

  select * into k from ingestion.identifier_keys
  where scheme = 'incorporated_association' and jurisdiction = 'AU-NSW'
    and normalized_value = ingestion.normalize_identifier('incorporated_association', 'AU-NSW', source.incorporation_number)
  for update;
  if k.id is null or k.holder <> item.target_organisation_id or k.state <> 'verified' then
    raise exception 'The merged identifier has changed since the correction; resolve it through identity review'
      using errcode = '55000';
  end if;

  review := jsonb_build_object('correction_id', item.correction_id, 'decision', p_decision,
    'note', note, 'reviewed_by', auth.uid(), 'reviewed_at', now());

  if p_decision = 'confirmed' then
    update ingestion.identifier_keys set
      evidence = evidence || jsonb_build_object('merge_review', review),
      revision = revision + 1, reviewed_by = auth.uid(), reviewed_at = now()
    where id = k.id;
  else
    if exists (select 1 from community_orgs.organisations where org_id = p_source) then
      raise exception 'The NSW association already exists' using errcode = '55000';
    end if;
    if not exists (select 1 from community_orgs.legal_details
      where org_id = item.target_organisation_id
        and incorporation_number is not distinct from source.incorporation_number) then
      raise exception 'The retained entity''s incorporation details have changed; edit them directly'
        using errcode = '55000';
    end if;

    -- Recreate exactly as apply_full_seed_union_batch did. The legal row goes in
    -- while the key is still held by the target, so it is not disputed.
    insert into community_orgs.organisations(org_id, entity_name, slug, is_public, inserted_by, last_edited_by)
    values (p_source, source.entity_name, 'seed-' || md5(source.canonical_key), true, auth.uid(), auth.uid());
    insert into community_orgs.legal_details(org_id, abn, entity_type, incorporation_number,
      incorporation_status, incorporation_registration_date, inserted_by, last_edited_by)
    values (p_source, source.abn, source.entity_type, source.incorporation_number,
      source.incorporation_status, source.incorporation_registration_date, auth.uid(), auth.uid());
    if source.website ~ '^https?://' then
      insert into community_orgs.contact_info(org_id, website, inserted_by, last_edited_by)
      values (p_source, source.website, auth.uid(), auth.uid());
    end if;
    update ingestion.field_state set protected = false
    where org_id = p_source and (table_name, field) in
      (('organisations', 'entity_name'), ('contact_info', 'website'));

    update ingestion.identifier_keys set
      holder = p_source,
      evidence = (evidence - 'seed_scope_correction_id' - 'name_match_method' - 'name_similarity_score')
        || jsonb_build_object('merge_review', review),
      revision = revision + 1, reviewed_by = auth.uid(), reviewed_at = now()
    where id = k.id;

    -- With the key moved, restoring the target's own values disputes nothing.
    update community_orgs.legal_details set
      incorporation_number = target.incorporation_number,
      incorporation_status = target.incorporation_status,
      incorporation_registration_date = target.incorporation_registration_date
    where org_id = item.target_organisation_id
      and incorporation_number is not distinct from source.incorporation_number;
    delete from community_orgs.aliases
    where org_id = item.target_organisation_id and alias_type is null
      and lower(alias) = lower(item.source_name);
  end if;

  insert into ingestion.seed_merge_reviews(correction_id, source_organisation_id, decision, note, reviewed_by)
  values (item.correction_id, p_source, p_decision, note, auth.uid());
  return jsonb_build_object('decision', p_decision, 'source_organisation_id', p_source,
    'target_organisation_id', item.target_organisation_id);
end
$$;

revoke all on function community_orgs.seed_merge_review_queue(text, text, integer, integer),
  community_orgs.review_seed_merge(uuid, text, text)
  from public, anon, service_role, ingestion_worker;
grant execute on function community_orgs.seed_merge_review_queue(text, text, integer, integer),
  community_orgs.review_seed_merge(uuid, text, text)
  to authenticated;

commit;
