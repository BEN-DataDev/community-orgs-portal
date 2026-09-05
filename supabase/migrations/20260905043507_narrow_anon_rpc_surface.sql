-- Withdraws EXECUTE from `anon` on the three community_orgs functions no
-- anonymous caller needs. Each one is reachable today at /rest/v1/rpc/<name>
-- without a session, which is what the advisor's
-- `anon_security_definer_function_executable` warnings report.
--
-- 20260905033103 deliberately left the whole helper set alone, and its reasoning
-- still holds for `authenticated` -- but it did not separate the two API roles.
-- The distinction matters: an RLS policy expression is evaluated as the
-- *invoking* role, so a policy that applies to anon needs anon to hold EXECUTE
-- on every function it names, or the query fails outright with "permission
-- denied for function" rather than simply returning no rows.
--
-- Kept for anon, because a policy anon can hit evaluates them:
--
--   * can_view_org, org_id_for_legal
--       20260904114055 writes `for select using (community_orgs.can_view_org(...))`
--       with no TO clause, so those SELECT policies apply to PUBLIC. This is
--       what makes the public organisation pages readable without signing in.
--   * user_has_permission
--       20260904111936's "organisation admins can view all roles" policy is
--       likewise a TO-less `for select`. It returns false for anon, since
--       auth.uid() is null -- but the EXECUTE check happens first.
--
-- Revoked below, because nothing anon does reaches them:
--
--   * can_edit_org
--       Named only by INSERT/UPDATE/DELETE policies, every one of which is
--       `to authenticated` (20260904114055, 20260905033915). An anon caller can
--       never have it evaluated on their behalf.
--   * generate_unique_slug
--       Called by the createOrganisation action, which sits behind authGuard
--       and so always runs with a session. It loops over organisations to find
--       a free slug, making it the one item here with a cost worth denying to
--       unauthenticated callers.
--   * user_max_role_level
--       Called by isSiteAdmin() in lib/server/authorization.ts, only on /admin
--       paths, which authGuard has already required a session for. The role
--       RPCs call it internally, and those calls are SECURITY DEFINER, so they
--       are unaffected by the caller's own grants.
--
-- Each function is revoked from `public` as well as `anon`. The baseline's
-- `grant all on all functions in schema community_orgs to anon, ...` is only
-- half the reason anon can call these: PostgreSQL also grants EXECUTE to PUBLIC
-- on every function at creation, and anon inherits that. Revoking from `anon`
-- alone would leave the PUBLIC grant standing and change nothing -- which is
-- why 20260905033103 revoked `from public, anon, authenticated` throughout.
--
-- Dropping PUBLIC takes the grant away from `authenticated` and `service_role`
-- too, so both are re-granted explicitly on the following lines. Those grants
-- already exist by name from the baseline; restating them keeps this migration
-- correct on its own terms rather than dependent on that.

revoke execute on function community_orgs.can_edit_org(uuid) from public, anon;
grant execute on function community_orgs.can_edit_org(uuid) to authenticated, service_role;

revoke execute on function community_orgs.generate_unique_slug(text) from public, anon;
grant execute on function community_orgs.generate_unique_slug(text) to authenticated, service_role;

revoke execute on function community_orgs.user_max_role_level(uuid, uuid) from public, anon;
grant execute on function community_orgs.user_max_role_level(uuid, uuid) to authenticated, service_role;
