-- Close execute paths left open by rename-and-wrap migrations and retire the
-- one-shot full-seed union RPCs. ALTER FUNCTION ... RENAME keeps the existing
-- ACL, so every renamed predecessor must also be revoked from authenticated.
begin;

-- Predecessors of gated wrappers: only the wrapper may reach them.
revoke all on function
  community_orgs.save_registry_seed_triage_before_three_source_gate(text,integer,text,text,text,text),
  community_orgs.promote_registry_seed_candidates_before_three_source_gate(text,text[],text),
  community_orgs.expire_registry_seed_raw_before_validation(text,boolean)
  from public,anon,authenticated,service_role,ingestion_worker;

-- Created by CREATE OR REPLACE without a revoke, so it inherited PUBLIC execute.
revoke all on function ingestion.reconciliation_missing_reason(bigint,bigint)
  from public,anon,authenticated,service_role,ingestion_worker;

-- The full-seed union bypassed triage, validation, three-source and release gates.
-- Its tables remain immutable audit evidence; the entry points are closed.
revoke all on function
  community_orgs.prepare_full_seed_union(text),
  community_orgs.apply_full_seed_union_batch(uuid,integer),
  community_orgs.full_seed_union_status(uuid)
  from public,anon,authenticated,service_role,ingestion_worker;

-- Superseded shim; the application calls the six-argument signature.
drop function community_orgs.configure_acnc_acquisition(text,text[],text,integer,text);

-- Revising replaces release contents, so it needs the same Data Steward authority
-- as submission and publication. Rejected releases stay rejected.
create or replace function community_orgs.revise_publication_release(
  p_release uuid, p_expected_revision integer, p_items jsonb, p_reason text
) returns integer language plpgsql security definer set search_path = '' as $$
declare rel ingestion.publication_releases; items jsonb; policy portal.publication_approval_policy; required integer; next_revision integer;
begin
  if portal.can_govern_publication_releases() is distinct from true then
    raise exception 'Release authority required' using errcode = '42501';
  end if;
  if community_orgs.is_data_steward() is distinct from true then
    raise exception 'Data Steward required to revise a release' using errcode = '42501';
  end if;
  if nullif(btrim(p_reason), '') is null or length(p_reason) > 2000 then
    raise exception 'A release reason is required' using errcode = '22023';
  end if;
  select * into rel from ingestion.publication_releases where release_id = p_release for update;
  if not found then raise exception 'Release not found' using errcode = 'P0002'; end if;
  if rel.status = 'published' then raise exception 'Published release is immutable' using errcode = '55000'; end if;
  if rel.status = 'rejected' then raise exception 'Rejected release cannot be revised; submit a new release' using errcode = '55000'; end if;
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

commit;
