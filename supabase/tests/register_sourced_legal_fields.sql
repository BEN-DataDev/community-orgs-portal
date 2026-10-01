-- Hosted-data check for 20261001061149_register_sourced_legal_fields and the DGR
-- lock added by 20261001062645_backfill_dgr_endorsement. Runs as a
-- throwaway owner of real seeded organisations: register-supplied legal columns
-- reject portal edits, other columns and non-register organisations stay editable,
-- and reviewed (non-API-role) paths are unaffected. Everything rolls back.
begin;

do $$
declare
  u uuid := '00000000-0000-4000-8000-00000000f1e1';
  full_org uuid;   -- holds ABR, ACNC and NSW records
  acnc_org uuid;   -- ABN from ACNC only, so its ABN status and DGR are not register-supplied
  own_org uuid := '00000000-0000-4000-8000-00000000f1e2';
  locked text[];
  field text;
  n int;
begin
  select o.org_id into full_org from community_orgs.organisations o
  where community_orgs.register_sourced_legal_fields(o.org_id)
    @> array['abn', 'abn_status', 'acnc_registered_date', 'incorporation_number']
  limit 1;
  select o.org_id into acnc_org from community_orgs.organisations o
  where community_orgs.register_sourced_legal_fields(o.org_id) = array['abn', 'acnc_registered_date']
  limit 1;
  if full_org is null or acnc_org is null then
    raise exception 'Needs seeded organisations with ABR+ACNC+NSW and ACNC-only records';
  end if;

  -- A portal-created organisation with no register record.
  insert into community_orgs.organisations(org_id, entity_name, slug)
  values (own_org, 'Register lock test organisation', 'register-lock-test');
  insert into community_orgs.legal_details(org_id, abn) values (own_org, '51824753556');
  if community_orgs.register_sourced_legal_fields(own_org) <> '{}' then
    raise exception 'Organisation without a register record has locked fields';
  end if;

  insert into auth.users(id, email, created_at, updated_at)
  values (u, 'register-lock-test@example.invalid', now(), now());
  insert into community_orgs.user_organisation_roles(user_id, organisation_id, role_id, granted_by, is_active)
  select u, org, r.id, u, true from community_orgs.roles r, unnest(array[full_org, acnc_org, own_org]) org
  where r.name = 'owner'
  on conflict do nothing;

  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated',
    'aal', 'aal1', 'is_anonymous', false)::text, true);
  set local role authenticated;

  -- Every register-supplied column rejects a change.
  locked := community_orgs.register_sourced_legal_fields(full_org);
  if cardinality(locked) <> 10 then raise exception 'Expected ten locked columns, got %', locked; end if;
  foreach field in array locked loop
    begin
      execute format(
        'update community_orgs.legal_details set %1$I = case when %1$I is null then %2$s else null end where org_id = $1',
        field,
        case field
          when 'abn' then quote_literal('51824753556')
          when 'incorporation_number' then quote_literal('INC9999999')
          when 'entity_type' then quote_literal('Trust')
          when 'abn_status' then 'true'
          when 'incorporation_status' then 'true'
          when 'dgr_endorsement' then 'true'
          else 'current_date' end)
        using full_org;
      raise exception 'Register-supplied % was edited', field;
    exception when insufficient_privilege then null;
    end;
  end loop;

  -- Clearing the row is also an edit of register data.
  begin
    delete from community_orgs.legal_details where org_id = full_org;
    raise exception 'Row holding register data was deleted';
  exception when insufficient_privilege then null;
  end;

  -- Other columns stay editable, including alongside unchanged register values,
  -- which is what an ordinary form save sends.
  update community_orgs.legal_details set last_annual_return_date = current_date, abn = abn, acn = '123456789'
  where org_id = full_org;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'Unlocked edit did not apply'; end if;

  -- An ABN from ACNC alone does not lock the ABR status or DGR columns.
  update community_orgs.legal_details
  set abn_status = false, abn_last_updated = current_date, dgr_endorsement = true
  where org_id = acnc_org;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'ABN status without an ABR record was not editable'; end if;
  begin
    update community_orgs.legal_details set acnc_registered_date = date '2000-01-01' where org_id = acnc_org;
    raise exception 'ACNC registration date was edited';
  exception when insufficient_privilege then null;
  end;

  -- Organisations outside the registers keep full control.
  update community_orgs.legal_details set abn = '33102417032', incorporation_number = 'INC0000001'
  where org_id = own_org;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'Portal-created organisation could not edit its ABN'; end if;
  delete from community_orgs.legal_details where org_id = own_org;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'Portal-created organisation could not clear its legal details'; end if;

  -- Provenance is not exposed to anonymous callers.
  reset role;
  set local role anon;
  begin
    perform community_orgs.register_sourced_legal_fields(full_org);
    raise exception 'Anonymous caller read register provenance';
  exception when insufficient_privilege then null;
  end;
  reset role;

  -- Reviewed workflows run as the function owner and are not restricted.
  update community_orgs.legal_details set abn_activated = abn_activated + 0
  where org_id = full_org;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'System path was blocked'; end if;
end $$;

rollback;

select 'Register-sourced legal fields lock passed' as result;
