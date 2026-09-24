begin;

insert into auth.users(id) values
  ('00000000-0000-4000-8000-000000000091'),
  ('00000000-0000-4000-8000-000000000092');
insert into platform_access.administrators(user_id, reason)
values ('00000000-0000-4000-8000-000000000091', 'Portal lifecycle test');

-- The primary key is a constant, so even different portal IDs cannot create a
-- second identity in one database.
insert into portal.configuration(
  portal_id, portal_key, display_name, short_name, sponsor_name,
  establishment_reason
) values (
  '10000000-0000-4000-8000-000000000001', 'test-portal',
  'Test Community Portal', 'Test Portal', 'Test Sponsor', 'Test establishment'
);

do $$
begin
  begin
    insert into portal.configuration(
      portal_id, portal_key, display_name, short_name, sponsor_name,
      establishment_reason
    ) values (
      '10000000-0000-4000-8000-000000000002', 'other-portal',
      'Other Portal', 'Other', 'Other Sponsor', 'Must fail'
    );
    raise exception 'Second portal identity was allowed';
  exception when unique_violation then null;
  end;

  if (select count(*) from portal.lifecycle_events) <> 1 then
    raise exception 'Establishment did not create exactly one lifecycle event';
  end if;

  set local role authenticated;
  perform set_config(
    'request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000092","aal":"aal2"}', true
  );
  begin
    perform community_orgs.transition_portal_lifecycle(
      'provisioned', 'Unauthorised transition', 'OPS-0', 1
    );
    raise exception 'Non-administrator lifecycle transition was allowed';
  exception when insufficient_privilege then null;
  end;

  perform set_config(
    'request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000091","aal":"aal2"}', true
  );

  if (select count(*) from community_orgs.get_portal_identity()) <> 1 then
    raise exception 'Public portal identity is unavailable';
  end if;
  perform community_orgs.transition_portal_lifecycle(
    'provisioned', 'Infrastructure provisioned', 'OPS-1', 1
  );
  begin
    perform community_orgs.transition_portal_lifecycle(
      'scope_configured', 'Scope accepted', null, 2
    );
    raise exception 'Scope transition without an authoritative revision was allowed';
  exception when invalid_parameter_value then null;
  end;
  perform community_orgs.configure_portal_scope(
    array['2720','2730'], 'test-policy-v1', 'Approved initial scope',
    'Initial test boundary; no existing acquisitions are affected.', false, 2
  );
  perform community_orgs.transition_portal_lifecycle(
    'scope_configured', 'Scope accepted', 'SCOPE-1', 3
  );
  begin
    perform community_orgs.transition_portal_lifecycle(
      'operational', 'Skipped establishment stages', 'REL-1', 4
    );
    raise exception 'Invalid lifecycle jump was allowed';
  exception when invalid_parameter_value then null;
  end;
  begin
    update portal.lifecycle_events set reason = 'rewritten';
    raise exception 'Lifecycle history was mutable';
  exception when insufficient_privilege then null;
  end;

  reset role;
  if (select scope_reference from portal.configuration) <> 'SCOPE-1' then
    raise exception 'Scope establishment reference was not retained';
  end if;
  if (select count(*) from portal.lifecycle_events) <> 3 then
    raise exception 'Lifecycle transition history is incomplete';
  end if;

  begin
    update portal.lifecycle_events set reason = 'rewritten';
    raise exception 'Lifecycle history trigger allowed a rewrite';
  exception when object_not_in_prerequisite_state then null;
  end;
end
$$;

rollback;
