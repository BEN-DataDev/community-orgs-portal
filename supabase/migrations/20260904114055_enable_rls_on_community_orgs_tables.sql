-- Enables row-level security on every community_orgs table that still had it
-- off. Until now the anon key could read and write all of them directly through
-- PostgREST, bypassing the application entirely.
--
-- Access follows the organisation: you can read a child record if you can see
-- its organisation (public, or you hold an active role), and change it if you
-- are an admin or owner of that organisation. Both tests go through the
-- SECURITY DEFINER helpers so the policies never re-enter RLS.

-- 1. Tables that carry org_id directly.
do $mig$
declare
    t text;
begin
    foreach t in array array[
        'accreditation', 'aliases', 'contact_info', 'documents',
        'financial_info', 'governance', 'historical_info', 'legal_details',
        'locations', 'operational_details', 'org_members', 'org_visibility',
        'performance_metrics', 'programs_services', 'relationships',
        'resources_assets'
    ]
    loop
        execute format('alter table community_orgs.%I enable row level security', t);

        execute format('drop policy if exists "read within organisation" on community_orgs.%I', t);
        execute format(
            'create policy "read within organisation" on community_orgs.%I '
            'for select using (community_orgs.can_view_org(org_id))', t);

        execute format('drop policy if exists "insert within organisation" on community_orgs.%I', t);
        execute format(
            'create policy "insert within organisation" on community_orgs.%I '
            'for insert to authenticated with check (community_orgs.can_edit_org(org_id))', t);

        execute format('drop policy if exists "update within organisation" on community_orgs.%I', t);
        execute format(
            'create policy "update within organisation" on community_orgs.%I '
            'for update to authenticated using (community_orgs.can_edit_org(org_id)) '
            'with check (community_orgs.can_edit_org(org_id))', t);

        execute format('drop policy if exists "delete within organisation" on community_orgs.%I', t);
        execute format(
            'create policy "delete within organisation" on community_orgs.%I '
            'for delete to authenticated using (community_orgs.can_edit_org(org_id))', t);
    end loop;
end
$mig$;

-- 2. dgr_endorsement reaches its organisation through legal_details.
alter table community_orgs.dgr_endorsement enable row level security;

drop policy if exists "read within organisation" on community_orgs.dgr_endorsement;
create policy "read within organisation" on community_orgs.dgr_endorsement
    for select using (community_orgs.can_view_org(community_orgs.org_id_for_legal(legal_id)));

drop policy if exists "insert within organisation" on community_orgs.dgr_endorsement;
create policy "insert within organisation" on community_orgs.dgr_endorsement
    for insert to authenticated
    with check (community_orgs.can_edit_org(community_orgs.org_id_for_legal(legal_id)));

drop policy if exists "update within organisation" on community_orgs.dgr_endorsement;
create policy "update within organisation" on community_orgs.dgr_endorsement
    for update to authenticated
    using (community_orgs.can_edit_org(community_orgs.org_id_for_legal(legal_id)))
    with check (community_orgs.can_edit_org(community_orgs.org_id_for_legal(legal_id)));

drop policy if exists "delete within organisation" on community_orgs.dgr_endorsement;
create policy "delete within organisation" on community_orgs.dgr_endorsement
    for delete to authenticated
    using (community_orgs.can_edit_org(community_orgs.org_id_for_legal(legal_id)));

-- 3. roles is reference data: readable by signed-in users, writable by nobody
--    through the API. The role-management functions are SECURITY DEFINER.
alter table community_orgs.roles enable row level security;

drop policy if exists "signed-in users can read role definitions" on community_orgs.roles;
create policy "signed-in users can read role definitions" on community_orgs.roles
    for select to authenticated using (true);

-- 4. role_audit_log is readable only by admins of the organisation concerned,
--    and is written solely by the SECURITY DEFINER grant/revoke functions.
alter table community_orgs.role_audit_log enable row level security;

drop policy if exists "organisation admins can read the audit log" on community_orgs.role_audit_log;
create policy "organisation admins can read the audit log" on community_orgs.role_audit_log
    for select to authenticated using (community_orgs.can_edit_org(organization_id));

-- 5. reserved_slugs gets RLS and deliberately no policy: no client needs it.
--    check_slug_not_reserved and generate_unique_slug are SECURITY DEFINER and
--    still read it.
alter table community_orgs.reserved_slugs enable row level security;
