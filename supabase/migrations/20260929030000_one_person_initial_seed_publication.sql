-- Permit an authorised Data Steward to complete a frozen initial seed without a
-- second actor. Suppression and destructive releases retain mandatory separation
-- of duties; ordinary updates retain the configured policy.
begin;

create or replace function community_orgs.submit_publication_release(
  p_release_class text, p_items jsonb, p_reason text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare release uuid; items jsonb; policy portal.publication_approval_policy; required integer; status text;
begin
  if portal.can_govern_publication_releases() is distinct from true then
    raise exception 'Release authority required' using errcode = '42501';
  end if;
  if community_orgs.is_data_steward() is distinct from true then
    raise exception 'Data Steward required to submit a release' using errcode = '42501';
  end if;
  if nullif(btrim(p_reason), '') is null or length(p_reason) > 2000 then
    raise exception 'A release reason is required' using errcode = '22023';
  end if;
  select * into policy from portal.publication_approval_policy where singleton for share;
  items := ingestion.normalise_publication_release_items(p_release_class, p_items);
  required := case
    when p_release_class in ('suppression', 'destructive') then 1
    when p_release_class = 'ordinary_update' and policy.ordinary_requires_independent_approval then 1
    else 0
  end;
  status := case when required = 0 then 'approved' else 'submitted' end;
  insert into ingestion.publication_releases(release_class, status, created_by)
  values (p_release_class, status, auth.uid()) returning release_id into release;
  insert into ingestion.publication_release_revisions(
    release_id, revision, items, content_sha256, reason, approval_policy_revision,
    required_independent_approvals, submitted_by
  ) values (
    release, 1, items, encode(sha256(convert_to(items::text, 'UTF8')), 'hex'), btrim(p_reason),
    policy.revision, required, auth.uid()
  );
  insert into ingestion.publication_release_events(release_id, revision, event_type, actor_id, detail)
  values (release, 1, 'submitted', auth.uid(), jsonb_build_object(
    'content_sha256', encode(sha256(convert_to(items::text, 'UTF8')), 'hex'),
    'approval_policy_revision', policy.revision, 'required_independent_approvals', required
  ));
  return release;
end
$$;

create or replace function community_orgs.revise_publication_release(
  p_release uuid, p_expected_revision integer, p_items jsonb, p_reason text
) returns integer language plpgsql security definer set search_path = '' as $$
declare rel ingestion.publication_releases; items jsonb; policy portal.publication_approval_policy; required integer; next_revision integer;
begin
  if portal.can_govern_publication_releases() is distinct from true then
    raise exception 'Release authority required' using errcode = '42501';
  end if;
  if nullif(btrim(p_reason), '') is null or length(p_reason) > 2000 then
    raise exception 'A release reason is required' using errcode = '22023';
  end if;
  select * into rel from ingestion.publication_releases where release_id = p_release for update;
  if not found then raise exception 'Release not found' using errcode = 'P0002'; end if;
  if rel.status = 'published' then raise exception 'Published release is immutable' using errcode = '55000'; end if;
  if rel.current_revision <> p_expected_revision then
    raise exception 'Release changed; reload' using errcode = '40001';
  end if;
  items := ingestion.normalise_publication_release_items(rel.release_class, p_items);
  select * into policy from portal.publication_approval_policy where singleton for share;
  required := case
    when rel.release_class in ('suppression', 'destructive') then 1
    when rel.release_class = 'ordinary_update' and policy.ordinary_requires_independent_approval then 1
    else 0
  end;
  next_revision := rel.current_revision + 1;
  insert into ingestion.publication_release_revisions(
    release_id, revision, items, content_sha256, reason, approval_policy_revision,
    required_independent_approvals, submitted_by
  ) values (p_release, next_revision, items, encode(sha256(convert_to(items::text, 'UTF8')), 'hex'),
    btrim(p_reason), policy.revision, required, auth.uid());
  update ingestion.publication_releases set current_revision = next_revision,
    status = case when required = 0 then 'approved' else 'submitted' end
  where release_id = p_release;
  insert into ingestion.publication_release_events(release_id, revision, event_type, actor_id, detail)
  values (p_release, next_revision, 'revised', auth.uid(), jsonb_build_object(
    'supersedes_revision', p_expected_revision,
    'content_sha256', encode(sha256(convert_to(items::text, 'UTF8')), 'hex'),
    'approval_policy_revision', policy.revision, 'required_independent_approvals', required
  ));
  return next_revision;
end
$$;

comment on function community_orgs.submit_publication_release(text, jsonb, text) is
  'Freezes a release. Initial seeds may be self-published by an authorised Data Steward; suppression and destructive releases require independent approval.';

commit;
