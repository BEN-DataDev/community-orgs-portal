-- Makes enrolling in TOTP multi-factor authentication actually mean something.
--
-- Once a user has a verified factor, their access tokens must carry aal2. An
-- aal1 token — one that signed in with a password or a magic link and then
-- never passed the second factor — sees nothing and can change nothing, whether
-- it arrives through this application or straight through PostgREST.
--
-- Users with no verified factor are unaffected: for them the check passes at
-- either level, so nothing changes until they opt in. That is the whole point of
-- this shape. Requiring aal2 unconditionally would lock out every existing
-- account the moment it shipped.

-- Does the caller have an authenticator app set up?
--
-- SECURITY DEFINER because `authenticated` has no grant on auth.mfa_factors —
-- only supabase_auth_admin and postgres do. The policy template in the Supabase
-- MFA guide queries that table inline, which on a current project makes every
-- statement fail with "permission denied for table mfa_factors" rather than
-- enforcing anything. Reading it through a definer function is what makes the
-- check work at all.
--
-- Empty search_path, matching the convention set in
-- 20260905033103_lock_trigger_fn_search_path.sql.
create or replace function community_orgs.user_has_verified_mfa()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from auth.mfa_factors
        where user_id = (select auth.uid())
          and status = 'verified'
    );
$$;

revoke all on function community_orgs.user_has_verified_mfa() from public, anon;
grant execute on function community_orgs.user_has_verified_mfa() to authenticated, service_role;

-- The policy itself.
--
-- RESTRICTIVE, not permissive. Permissive policies are OR-ed together, so a
-- permissive version of this would be satisfied by any other policy that
-- happened to pass and would enforce nothing at all.
--
-- Read the assurance levels as a pair:
--   aal1 / aal1  no factor enrolled
--   aal1 / aal2  factor enrolled, challenge not yet passed  <- blocked here
--   aal2 / aal2  factor enrolled and verified this session
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
            'alter table community_orgs.%I enable row level security', t);

        execute format(
            'drop policy if exists "enrolled users must pass mfa" on community_orgs.%I', t);

        execute format(
            'create policy "enrolled users must pass mfa" on community_orgs.%I '
            'as restrictive to authenticated '
            'using ( '
            '  not community_orgs.user_has_verified_mfa() '
            '  or (select auth.jwt() ->> ''aal'') = ''aal2'' '
            ')', t);
    end loop;
end
$mig$;
