begin;

insert into auth.users(id) values ('00000000-0000-4000-8000-000000000093');
insert into platform_access.administrators(user_id, reason)
values ('00000000-0000-4000-8000-000000000093', 'Portal scope test');
insert into ingestion.operators(user_id)
values ('00000000-0000-4000-8000-000000000093');
insert into portal.configuration(
  portal_id, portal_key, display_name, short_name, sponsor_name, establishment_reason
) values (
  '10000000-0000-4000-8000-000000000003', 'scope-test',
  'Scope Test Portal', 'Scope Test', 'Test Sponsor', 'PEG02 regression'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000093","aal":"aal2"}', true
);

do $$
declare
  scope_one bigint;
  scope_two bigint;
  job uuid;
  run_one bigint;
  run_two bigint;
  reason text;
begin
  begin
    perform community_orgs.configure_portal_scope(
      array['2730','2720'], 'policy-v1', 'Unsorted scope', 'Must fail', false, 1
    );
    raise exception 'Unsorted scope was accepted';
  exception when invalid_parameter_value then null;
  end;

  scope_one := community_orgs.configure_portal_scope(
    array['2720','2730'], 'policy-v1', 'Initial approved boundary',
    'No earlier scope or acquisition exists.', false, 1
  );
  reset role;
  if (select configuration_revision from portal.configuration) <> 2
     or (select current_scope_revision_id from portal.configuration) <> scope_one
     or (select array_agg(postcode order by postcode) from portal.scope_postcodes
         where scope_revision_id = scope_one) <> array['2720','2730'] then
    raise exception 'Initial authoritative scope was not recorded canonically';
  end if;

  set local role authenticated;
  begin
    perform community_orgs.configure_portal_scope(
      array['2720','2730'], 'policy-v2', 'No postcode change', 'Must fail', false, 2
    );
    raise exception 'Unchanged postcode revision was accepted';
  exception when invalid_parameter_value then null;
  end;

  reset role;
  insert into ingestion.sources(source_id, resource_id, metadata, enabled)
  values ('acnc-register', '00000000-0000-4000-8000-000000000094', '{}', true);
  set local role authenticated;
  begin
    perform community_orgs.configure_acnc_acquisition(
      '00000000-0000-4000-8000-000000000094', array['2720'],
      'Reviewed licence', null, '0', null
    );
    raise exception 'Subset without a justification was accepted';
  exception when invalid_parameter_value then null;
  end;
  perform community_orgs.configure_acnc_acquisition(
    '00000000-0000-4000-8000-000000000094', array['2720'],
    'Reviewed licence', null, '0', 'Provider pilot intentionally uses a bounded subset'
  );
  reset role;
  if not exists (select 1 from ingestion.acquisition_configs
    where scope_revision_id = scope_one and scope_alignment = 'subset') then
    raise exception 'Acquisition was not attributed to its portal scope revision';
  end if;
  set local role authenticated;
  job := community_orgs.enqueue_acnc_acquisition(
    '00000000-0000-4000-8000-000000000094'
  )::uuid;

  scope_two := community_orgs.configure_portal_scope(
    array['2720','2730','2731'], 'policy-v2', 'Approved scope expansion',
    'One postcode is added; existing evidence remains on revision 1.', true, 2
  );
  reset role;
  if not exists (select 1 from portal.scope_revisions
    where id = scope_two and revision = 2 and previous_revision_id = scope_one
      and requires_rebaseline) then
    raise exception 'Scope history did not link revision 2 to revision 1';
  end if;
  if not exists (select 1 from ingestion.acquisition_jobs
    where id = job and status = 'cancelled' and message = 'Portal scope revision changed.') then
    raise exception 'Scope change did not cancel obsolete acquisition work';
  end if;
  set local role authenticated;
  begin
    perform community_orgs.enqueue_acnc_acquisition(
      '00000000-0000-4000-8000-000000000094'
    );
    raise exception 'Obsolete acquisition configuration was queued';
  exception when object_not_in_prerequisite_state then null;
  end;

  reset role;
  begin
    update portal.scope_revisions set reason = 'rewritten' where id = scope_one;
    raise exception 'Scope revision was mutable';
  exception when object_not_in_prerequisite_state then null;
  end;
  begin
    delete from portal.scope_postcodes where scope_revision_id = scope_one;
    raise exception 'Scope postcode history was mutable';
  exception when object_not_in_prerequisite_state then null;
  end;

  insert into ingestion.ingestion_runs(
    source_id, resource_id, run_key, completion, observed_at, envelope
  ) values (
    'acnc-register', '00000000-0000-4000-8000-000000000094', 'scope-one', 'complete',
    '2026-09-23T00:00:00Z', '{"scope":{"portal_scope_revision_id":"1"},"errors":[],"quarantine":[]}'
  ) returning id into run_one;
  insert into ingestion.ingestion_runs(
    source_id, resource_id, run_key, completion, observed_at, envelope
  ) values (
    'acnc-register', '00000000-0000-4000-8000-000000000094', 'scope-two', 'complete',
    '2026-09-24T00:00:00Z', '{"scope":{"portal_scope_revision_id":"2"},"errors":[],"quarantine":[]}'
  ) returning id into run_two;
  reason := ingestion.reconciliation_missing_reason(run_two, run_one);
  if reason not like 'Baseline uses an incompatible portal scope revision%' then
    raise exception 'Reconciliation did not reject incompatible portal scopes: %', reason;
  end if;
end
$$;

rollback;
