-- Confines anonymous users to reading public organisations.
--
-- `signInAnonymously()` issues a real session holding the same `authenticated`
-- Postgres role as everyone else. Nothing in the existing policies distinguishes
-- the two, so without this migration enabling anonymous sign-ins would hand a
-- guest the same write access as a signed-up member. The only thing that tells
-- them apart is the `is_anonymous` claim on the JWT.
--
-- Reads of public organisations need no new policy. `can_view_org` already
-- admits a row when the organisation is public *or* the caller holds an active
-- role on it, and an anonymous user holds no roles, so they fall through to the
-- public branch on their own.
--
-- All policies here are RESTRICTIVE. Permissive policies are OR-ed together, so
-- a permissive version of any of these would be satisfied by an existing policy
-- and enforce nothing.

-- 1. No anonymous writes anywhere in the schema.
--
--    Split across the three write commands rather than written as one `for all`
--    policy: `for all` would cover SELECT too, which is exactly the access
--    guests are supposed to have.
do $mig$
declare
    t text;
begin
    for t in
        select tablename
        from pg_tables
        where schemaname = 'community_orgs'
        order by tablename
    loop
        execute format(
            'drop policy if exists "no anonymous insert" on community_orgs.%I', t);
        execute format(
            'create policy "no anonymous insert" on community_orgs.%I '
            'as restrictive for insert to authenticated '
            'with check ((select (auth.jwt() ->> ''is_anonymous'')::boolean) is not true)', t);

        execute format(
            'drop policy if exists "no anonymous update" on community_orgs.%I', t);
        execute format(
            'create policy "no anonymous update" on community_orgs.%I '
            'as restrictive for update to authenticated '
            'using ((select (auth.jwt() ->> ''is_anonymous'')::boolean) is not true) '
            'with check ((select (auth.jwt() ->> ''is_anonymous'')::boolean) is not true)', t);

        execute format(
            'drop policy if exists "no anonymous delete" on community_orgs.%I', t);
        execute format(
            'create policy "no anonymous delete" on community_orgs.%I '
            'as restrictive for delete to authenticated '
            'using ((select (auth.jwt() ->> ''is_anonymous'')::boolean) is not true)', t);
    end loop;
end
$mig$;

-- 2. Some tables stay closed to guests even on a public organisation.
--
--    "This organisation is public" means the public may see what it does — not
--    its bank details, its office bearers' contact details, or who holds which
--    role in it. Those child records are only visible to someone who has
--    actually signed up.
do $mig$
declare
    t text;
begin
    foreach t in array array[
        'contact_info',       -- personal phone numbers and addresses
        'financial_info',     -- bank and revenue details
        'legal_details',      -- ABN/ACN, constitution, regulator correspondence
        'dgr_endorsement',    -- hangs off legal_details
        'documents',          -- uploaded files, not vetted for public release
        'governance',         -- named office bearers
        'org_members',        -- named members
        'role_audit_log',
        'role_requests',
        'user_organisation_roles'
    ]
    loop
        execute format(
            'drop policy if exists "no anonymous read" on community_orgs.%I', t);
        execute format(
            'create policy "no anonymous read" on community_orgs.%I '
            'as restrictive for select to authenticated '
            'using ((select (auth.jwt() ->> ''is_anonymous'')::boolean) is not true)', t);
    end loop;
end
$mig$;

-- 3. Housekeeping for abandoned guest sessions.
--
--    Anonymous users are rows in auth.users that nobody will ever sign back in
--    as, and they accumulate. Called from the scheduled job in
--    src/routes/api/cron/+server.ts rather than granting that endpoint direct
--    access to auth.users.
--
--    SECURITY DEFINER with an empty search_path, matching the convention set in
--    20260905033103_lock_trigger_fn_search_path.sql.
create or replace function community_orgs.purge_stale_anonymous_users(
    p_older_than interval default interval '30 days'
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_deleted integer;
begin
    delete from auth.users
     where is_anonymous is true
       and created_at < now() - p_older_than;

    get diagnostics v_deleted = row_count;
    return v_deleted;
end;
$$;

-- Only the scheduled job runs this, and it holds the service role key.
revoke all on function community_orgs.purge_stale_anonymous_users(interval)
    from public, anon, authenticated;
grant execute on function community_orgs.purge_stale_anonymous_users(interval)
    to service_role;
