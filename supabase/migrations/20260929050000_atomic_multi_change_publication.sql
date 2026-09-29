-- Validate every frozen identity decision against one starting revision before an
-- atomic release applies any of its own identity-changing writes. The portal table
-- lock prevents external identity changes between validation and publication.
begin;

create or replace function community_orgs.publish_publication_release(p_release uuid, p_revision integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare rel ingestion.publication_releases; rev ingestion.publication_release_revisions;
  item jsonb; c ingestion.change_sets; actual_hash text; org uuid; result jsonb := '[]';
  starting_identity_revision bigint;
begin
  if portal.can_govern_publication_releases() is distinct from true then
    raise exception 'Release authority required' using errcode = '42501';
  end if;
  if community_orgs.is_data_steward() is distinct from true then
    raise exception 'Data Steward required to publish' using errcode = '42501';
  end if;
  lock table community_orgs.organisations in share row exclusive mode;
  select revision into starting_identity_revision from ingestion.identity_clock where singleton;
  select * into rel from ingestion.publication_releases where release_id = p_release for update;
  if not found then raise exception 'Release not found' using errcode = 'P0002'; end if;
  if rel.status = 'published' and rel.current_revision = p_revision then return rel.publication_result; end if;
  if rel.current_revision <> p_revision or rel.status <> 'approved' then
    raise exception 'Exact approved release revision required' using errcode = '40001';
  end if;
  select * into rev from ingestion.publication_release_revisions
   where release_id = p_release and revision = p_revision for share;
  if rev.required_independent_approvals = 1 and not exists(
    select 1 from ingestion.publication_release_decisions d
    where d.release_id = p_release and d.revision = p_revision and d.decision = 'approved'
      and d.decided_by <> rev.submitted_by
  ) then raise exception 'Independent approval required' using errcode = '42501'; end if;
  if rev.content_sha256 <> encode(sha256(convert_to(rev.items::text, 'UTF8')), 'hex') then
    raise exception 'Release contents changed' using errcode = '55000';
  end if;

  -- Preflight the complete batch before the first write. This is the same identity
  -- fence used by single-change publication, evaluated once for the atomic release.
  for item in select value from jsonb_array_elements(rev.items) loop
    if item->>'action' = 'publish_change_set' then
      select * into c from ingestion.change_sets where id = (item->>'change_set_id')::uuid for update;
      if not found then raise exception 'Change set not found' using errcode = 'P0002'; end if;
      actual_hash := encode(sha256(convert_to(jsonb_build_object(
        'run_id', c.run_id, 'version_id', c.version_id,
        'review_revision', c.review_revision, 'organisation_id', c.organisation_id,
        'fields', c.fields, 'approved_by', c.approved_by, 'identity_revision', c.identity_revision
      )::text, 'UTF8')), 'hex');
      if actual_hash is distinct from item->>'snapshot_sha256' then
        raise exception 'Frozen change set changed; revise release' using errcode = '40001';
      end if;
      if not exists(select 1 from ingestion.publications where change_set_id = c.id) then
        if c.identity_revision is distinct from starting_identity_revision then
          raise exception 'Identity changed; approve again' using errcode = '40001';
        end if;
        perform ingestion.assert_identity_target(c.version_id, c.organisation_id);
      end if;
    elsif item->>'action' <> 'suppress_content' then
      raise exception 'Unsupported release action' using errcode = '22023';
    end if;
  end loop;

  for item in select value from jsonb_array_elements(rev.items) loop
    if item->>'action' = 'publish_change_set' then
      select * into c from ingestion.change_sets where id = (item->>'change_set_id')::uuid;
      -- Identity was fenced for the whole batch above. Calling the mature writer
      -- below the single-item identity wrapper prevents this release's first write
      -- from invalidating its remaining frozen items.
      org := community_orgs.publish_ingestion_fields_before_identity(c.id);
      result := result || jsonb_build_array(jsonb_build_object(
        'action', 'publish_change_set', 'change_set_id', c.id, 'organisation_id', org
      ));
    else
      perform community_orgs.suppress_ingestion_content_before_release_approval(
        item->>'run', item->>'version', item->>'field', item->>'reason', item->'expected'
      );
      result := result || jsonb_build_array(jsonb_build_object(
        'action', 'suppress_content', 'run', item->>'run',
        'version', item->>'version', 'field', item->>'field'
      ));
    end if;
  end loop;
  update ingestion.publication_releases set status = 'published', published_at = now(),
    published_by = auth.uid(), publication_result = result where release_id = p_release;
  insert into ingestion.publication_release_events(release_id, revision, event_type, actor_id, detail)
  values (p_release, p_revision, 'published', auth.uid(), jsonb_build_object(
    'content_sha256', rev.content_sha256, 'writes', result
  ));
  return result;
end
$$;

comment on function community_orgs.publish_publication_release(uuid, integer) is
  'Atomically publishes an exact approved revision after batch-wide frozen snapshot and identity preflight.';

commit;
