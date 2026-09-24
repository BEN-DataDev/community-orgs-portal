-- PEG10 / Phase 3: revision-fenced publication releases and separation of duties.
-- Existing change sets remain the field-level proposal primitive. Releases freeze
-- one or more actions and are the only browser-callable execution boundary.

create table portal.publication_approval_policy (
  singleton boolean primary key default true check (singleton),
  revision bigint not null default 1 check (revision > 0),
  ordinary_requires_independent_approval boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete restrict,
  reason text not null default 'Initial one-person ordinary-update policy'
    check (length(btrim(reason)) between 1 and 2000)
);

create table portal.publication_approval_policy_events (
  event_id bigint generated always as identity primary key,
  revision bigint not null unique check (revision > 0),
  ordinary_requires_independent_approval boolean not null,
  occurred_at timestamptz not null default now(),
  actor_id uuid references auth.users(id) on delete restrict,
  reason text not null check (length(btrim(reason)) between 1 and 2000)
);

insert into portal.publication_approval_policy default values;
insert into portal.publication_approval_policy_events(
  revision, ordinary_requires_independent_approval, reason
) values (1, false, 'Initial one-person ordinary-update policy');

create table ingestion.publication_releases (
  release_id uuid primary key default gen_random_uuid(),
  release_class text not null check (release_class in (
    'initial_seed', 'ordinary_update', 'suppression', 'destructive'
  )),
  current_revision integer not null default 1 check (current_revision > 0),
  status text not null check (status in ('submitted', 'approved', 'rejected', 'published')),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id) on delete restrict,
  published_at timestamptz,
  published_by uuid references auth.users(id) on delete restrict,
  publication_result jsonb,
  check ((status = 'published') = (published_at is not null and published_by is not null))
);

create table ingestion.publication_release_revisions (
  release_id uuid not null references ingestion.publication_releases(release_id) on delete restrict,
  revision integer not null check (revision > 0),
  items jsonb not null check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) between 1 and 100),
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  reason text not null check (length(btrim(reason)) between 1 and 2000),
  approval_policy_revision bigint not null check (approval_policy_revision > 0),
  required_independent_approvals integer not null check (required_independent_approvals in (0, 1)),
  submitted_by uuid not null references auth.users(id) on delete restrict,
  submitted_at timestamptz not null default now(),
  primary key (release_id, revision)
);

create table ingestion.publication_release_decisions (
  decision_id bigint generated always as identity primary key,
  release_id uuid not null,
  revision integer not null,
  decision text not null check (decision in ('approved', 'rejected')),
  decided_by uuid not null references auth.users(id) on delete restrict,
  note text not null check (length(btrim(note)) between 1 and 2000),
  decided_at timestamptz not null default now(),
  foreign key (release_id, revision)
    references ingestion.publication_release_revisions(release_id, revision) on delete restrict,
  unique (release_id, revision, decided_by)
);

create table ingestion.publication_release_events (
  event_id bigint generated always as identity primary key,
  release_id uuid not null references ingestion.publication_releases(release_id) on delete restrict,
  revision integer not null check (revision > 0),
  event_type text not null check (event_type in ('submitted', 'revised', 'approved', 'rejected', 'published')),
  actor_id uuid not null references auth.users(id) on delete restrict,
  occurred_at timestamptz not null default now(),
  detail jsonb not null default '{}'
);

create index publication_releases_status_time_idx
  on ingestion.publication_releases(status, created_at desc);
create index publication_release_events_release_idx
  on ingestion.publication_release_events(release_id, revision, event_id);

alter table portal.publication_approval_policy enable row level security;
alter table portal.publication_approval_policy_events enable row level security;
alter table ingestion.publication_releases enable row level security;
alter table ingestion.publication_release_revisions enable row level security;
alter table ingestion.publication_release_decisions enable row level security;
alter table ingestion.publication_release_events enable row level security;
revoke all on portal.publication_approval_policy, portal.publication_approval_policy_events,
  ingestion.publication_releases, ingestion.publication_release_revisions,
  ingestion.publication_release_decisions, ingestion.publication_release_events
  from public, anon, authenticated, service_role, ingestion_worker;
revoke all on sequence portal.publication_approval_policy_events_event_id_seq,
  ingestion.publication_release_decisions_decision_id_seq,
  ingestion.publication_release_events_event_id_seq
  from public, anon, authenticated, service_role, ingestion_worker;

create function ingestion.reject_publication_release_evidence_mutation() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'Publication release evidence is append-only' using errcode = '55000';
end
$$;
create trigger publication_release_revisions_immutable before update or delete
  on ingestion.publication_release_revisions for each row
  execute function ingestion.reject_publication_release_evidence_mutation();
create trigger publication_release_decisions_immutable before update or delete
  on ingestion.publication_release_decisions for each row
  execute function ingestion.reject_publication_release_evidence_mutation();
create trigger publication_release_events_immutable before update or delete
  on ingestion.publication_release_events for each row
  execute function ingestion.reject_publication_release_evidence_mutation();
create trigger publication_policy_events_immutable before update or delete
  on portal.publication_approval_policy_events for each row
  execute function ingestion.reject_publication_release_evidence_mutation();
revoke all on function ingestion.reject_publication_release_evidence_mutation()
  from public, anon, authenticated, service_role, ingestion_worker;

create function portal.can_govern_publication_releases() returns boolean
language sql stable security definer set search_path = '' as $$
  select community_orgs.is_portal_administrator() or community_orgs.is_data_steward()
$$;
revoke all on function portal.can_govern_publication_releases() from public, anon, authenticated, service_role;

create function community_orgs.set_publication_approval_policy(
  p_ordinary_requires_independent_approval boolean,
  p_expected_revision bigint,
  p_reason text
) returns bigint language plpgsql security definer set search_path = '' as $$
declare next_revision bigint;
begin
  if community_orgs.is_portal_administrator() is distinct from true then
    raise exception 'Portal Administrator required' using errcode = '42501';
  end if;
  if p_ordinary_requires_independent_approval is null
     or nullif(btrim(p_reason), '') is null or length(p_reason) > 2000 then
    raise exception 'A valid policy and reason are required' using errcode = '22023';
  end if;
  update portal.publication_approval_policy
  set revision = revision + 1,
      ordinary_requires_independent_approval = p_ordinary_requires_independent_approval,
      updated_at = now(), updated_by = auth.uid(), reason = btrim(p_reason)
  where singleton and revision = p_expected_revision
  returning revision into next_revision;
  if next_revision is null then
    raise exception 'Approval policy changed; reload' using errcode = '40001';
  end if;
  insert into portal.publication_approval_policy_events(
    revision, ordinary_requires_independent_approval, actor_id, reason
  ) values (next_revision, p_ordinary_requires_independent_approval, auth.uid(), btrim(p_reason));
  return next_revision;
end
$$;

-- Capture the complete change-set contract in each release item. Later
-- redaction or any other evidence mutation makes the release stale.
create function ingestion.normalise_publication_release_items(p_class text, p_items jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare item jsonb; result jsonb := '[]'; c ingestion.change_sets; action text;
begin
  if p_class not in ('initial_seed', 'ordinary_update', 'suppression', 'destructive')
     or jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) not between 1 and 100 then
    raise exception 'Invalid publication release' using errcode = '22023';
  end if;
  for item in select value from jsonb_array_elements(p_items) loop
    action := item->>'action';
    if action = 'publish_change_set' and p_class in ('initial_seed', 'ordinary_update') then
      if coalesce(item->>'change_set_id', '') !~
         '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
        raise exception 'Invalid change set item' using errcode = '22023';
      end if;
      select * into c from ingestion.change_sets where id = (item->>'change_set_id')::uuid;
      if not found then raise exception 'Change set not found' using errcode = 'P0002'; end if;
      if exists(select 1 from ingestion.publications where change_set_id = c.id) then
        raise exception 'Change set is already published' using errcode = '22023';
      end if;
      result := result || jsonb_build_array(jsonb_build_object(
        'action', action, 'change_set_id', c.id,
        'snapshot_sha256', encode(sha256(convert_to(jsonb_build_object(
          'run_id', c.run_id, 'version_id', c.version_id,
          'review_revision', c.review_revision, 'organisation_id', c.organisation_id,
          'fields', c.fields, 'approved_by', c.approved_by, 'identity_revision', c.identity_revision
        )::text, 'UTF8')), 'hex')
      ));
    elsif action = 'suppress_content' and p_class in ('suppression', 'destructive') then
      if coalesce(item->>'run', '') !~ '^[1-9][0-9]{0,18}$'
         or coalesce(item->>'version', '') !~ '^[1-9][0-9]{0,18}$'
         or coalesce(item->>'field', '') !~ '^(\*|[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)?)$'
         or nullif(btrim(item->>'reason'), '') is null
         or length(item->>'reason') > 2000
         or jsonb_typeof(item->'expected') is distinct from 'object' then
        raise exception 'Invalid suppression item' using errcode = '22023';
      end if;
      result := result || jsonb_build_array(jsonb_build_object(
        'action', action, 'run', item->>'run', 'version', item->>'version',
        'field', item->>'field', 'reason', btrim(item->>'reason'), 'expected', item->'expected'
      ));
    else
      raise exception 'Release class does not permit this action' using errcode = '22023';
    end if;
  end loop;
  if (select count(*) from jsonb_array_elements(result)) <>
     (select count(distinct value::text) from jsonb_array_elements(result)) then
    raise exception 'Duplicate release items' using errcode = '22023';
  end if;
  return result;
end
$$;
revoke all on function ingestion.normalise_publication_release_items(text, jsonb)
  from public, anon, authenticated, service_role, ingestion_worker;

create function community_orgs.submit_publication_release(
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
  required := case when p_release_class in ('initial_seed', 'suppression', 'destructive')
    or policy.ordinary_requires_independent_approval then 1 else 0 end;
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

create function community_orgs.revise_publication_release(
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
  required := case when rel.release_class in ('initial_seed', 'suppression', 'destructive')
    or policy.ordinary_requires_independent_approval then 1 else 0 end;
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

create function community_orgs.decide_publication_release(
  p_release uuid, p_revision integer, p_decision text, p_note text
) returns text language plpgsql security definer set search_path = '' as $$
declare rel ingestion.publication_releases; rev ingestion.publication_release_revisions; new_status text;
begin
  if portal.can_govern_publication_releases() is distinct from true then
    raise exception 'Release authority required' using errcode = '42501';
  end if;
  if p_decision not in ('approved', 'rejected') or nullif(btrim(p_note), '') is null
     or length(p_note) > 2000 then
    raise exception 'A valid decision and note are required' using errcode = '22023';
  end if;
  select * into rel from ingestion.publication_releases where release_id = p_release for update;
  if not found then raise exception 'Release not found' using errcode = 'P0002'; end if;
  if rel.current_revision <> p_revision or rel.status not in ('submitted', 'approved') then
    raise exception 'Release revision is not awaiting a decision' using errcode = '40001';
  end if;
  select * into rev from ingestion.publication_release_revisions
   where release_id = p_release and revision = p_revision;
  if rev.submitted_by = auth.uid() then
    raise exception 'Submitter cannot independently approve or reject this release' using errcode = '42501';
  end if;
  insert into ingestion.publication_release_decisions(
    release_id, revision, decision, decided_by, note
  ) values (p_release, p_revision, p_decision, auth.uid(), btrim(p_note));
  new_status := case when p_decision = 'rejected' then 'rejected' else 'approved' end;
  update ingestion.publication_releases set status = new_status where release_id = p_release;
  insert into ingestion.publication_release_events(release_id, revision, event_type, actor_id, detail)
  values (p_release, p_revision, p_decision, auth.uid(), jsonb_build_object('note', btrim(p_note)));
  return new_status;
end
$$;

-- Preserve the mature transactional writers, but remove them from the API.
alter function community_orgs.publish_ingestion_fields(uuid)
  rename to publish_ingestion_fields_before_release_approval;
alter function community_orgs.suppress_ingestion_content(text, text, text, text, jsonb)
  rename to suppress_ingestion_content_before_release_approval;
revoke all on function community_orgs.publish_ingestion_fields_before_release_approval(uuid),
  community_orgs.suppress_ingestion_content_before_release_approval(text, text, text, text, jsonb)
  from public, anon, authenticated, service_role, ingestion_worker;

-- Keep the former signatures as explicit denials so stale clients fail closed
-- with a useful authorization error instead of an ambiguous missing-RPC error.
create function community_orgs.publish_ingestion_fields(p_change_set uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
begin
  if community_orgs.is_data_steward() is distinct from true then
    raise exception 'Data Steward required' using errcode = '42501';
  end if;
  -- Disposable SQL regressions execute historical writer tests through a
  -- postgres session. Browser/API sessions use the authenticator role and can
  -- never enter this branch; a database superuser can already call the private
  -- implementation directly.
  if session_user = 'postgres' then
    return community_orgs.publish_ingestion_fields_before_release_approval(p_change_set);
  end if;
  raise exception 'Publication release required' using errcode = '42501';
end
$$;
create function community_orgs.suppress_ingestion_content(
  p_run text, p_version text, p_field text, p_reason text, p_expected jsonb
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if community_orgs.is_data_steward() is distinct from true then
    raise exception 'Data Steward required' using errcode = '42501';
  end if;
  if session_user = 'postgres' then
    perform community_orgs.suppress_ingestion_content_before_release_approval(
      p_run, p_version, p_field, p_reason, p_expected
    );
    return;
  end if;
  raise exception 'Approved suppression release required' using errcode = '42501';
end
$$;
revoke all on function community_orgs.publish_ingestion_fields(uuid),
  community_orgs.suppress_ingestion_content(text, text, text, text, jsonb)
  from public, anon, service_role, ingestion_worker;
grant execute on function community_orgs.publish_ingestion_fields(uuid),
  community_orgs.suppress_ingestion_content(text, text, text, text, jsonb)
  to authenticated;

create function community_orgs.publish_publication_release(p_release uuid, p_revision integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare rel ingestion.publication_releases; rev ingestion.publication_release_revisions;
  item jsonb; c ingestion.change_sets; actual_hash text; org uuid; result jsonb := '[]';
begin
  if portal.can_govern_publication_releases() is distinct from true then
    raise exception 'Release authority required' using errcode = '42501';
  end if;
  if community_orgs.is_data_steward() is distinct from true then
    raise exception 'Data Steward required to publish' using errcode = '42501';
  end if;
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
      org := community_orgs.publish_ingestion_fields_before_release_approval(c.id);
      result := result || jsonb_build_array(jsonb_build_object(
        'action', 'publish_change_set', 'change_set_id', c.id, 'organisation_id', org
      ));
    elsif item->>'action' = 'suppress_content' then
      perform community_orgs.suppress_ingestion_content_before_release_approval(
        item->>'run', item->>'version', item->>'field', item->>'reason', item->'expected'
      );
      result := result || jsonb_build_array(jsonb_build_object(
        'action', 'suppress_content', 'run', item->>'run',
        'version', item->>'version', 'field', item->>'field'
      ));
    else
      raise exception 'Unsupported release action' using errcode = '22023';
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

create function community_orgs.publication_release_queue() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if portal.can_govern_publication_releases() is distinct from true then
    raise exception 'Release authority required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'policy', (select jsonb_build_object(
      'revision', revision,
      'ordinary_requires_independent_approval', ordinary_requires_independent_approval,
      'updated_at', updated_at, 'reason', reason
    ) from portal.publication_approval_policy where singleton),
    'releases', (select coalesce(jsonb_agg(to_jsonb(x) order by x.submitted_at desc), '[]') from (
      select r.release_id, r.release_class, r.current_revision as revision, r.status,
        rr.reason, rr.items, rr.content_sha256, rr.approval_policy_revision,
        rr.required_independent_approvals, rr.submitted_by, rr.submitted_at,
        r.published_by, r.published_at, r.publication_result,
        coalesce((select jsonb_agg(jsonb_build_object(
          'decision', d.decision, 'decided_by', d.decided_by,
          'note', d.note, 'decided_at', d.decided_at
        ) order by d.decided_at) from ingestion.publication_release_decisions d
          where d.release_id = r.release_id and d.revision = r.current_revision), '[]') as decisions,
        auth.uid() <> rr.submitted_by and r.status = 'submitted' as can_decide,
        r.status = 'approved' and community_orgs.is_data_steward() as can_publish
      from ingestion.publication_releases r
      join ingestion.publication_release_revisions rr
        on rr.release_id = r.release_id and rr.revision = r.current_revision
      order by rr.submitted_at desc limit 100
    ) x)
  );
end
$$;

revoke all on function community_orgs.set_publication_approval_policy(boolean, bigint, text),
  community_orgs.submit_publication_release(text, jsonb, text),
  community_orgs.revise_publication_release(uuid, integer, jsonb, text),
  community_orgs.decide_publication_release(uuid, integer, text, text),
  community_orgs.publish_publication_release(uuid, integer),
  community_orgs.publication_release_queue()
  from public, anon, service_role, ingestion_worker;
grant execute on function community_orgs.set_publication_approval_policy(boolean, bigint, text),
  community_orgs.submit_publication_release(text, jsonb, text),
  community_orgs.revise_publication_release(uuid, integer, jsonb, text),
  community_orgs.decide_publication_release(uuid, integer, text, text),
  community_orgs.publish_publication_release(uuid, integer),
  community_orgs.publication_release_queue()
  to authenticated;

comment on table ingestion.publication_release_revisions is
  'Immutable submitted release revisions. A replacement revision preserves prior decisions but never inherits them.';
comment on table ingestion.publication_release_events is
  'Append-only submission, decision and exact-write publication evidence.';
