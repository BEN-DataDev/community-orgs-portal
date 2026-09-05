-- Follow-up to 20260905031617, clearing the rest of the community_orgs
-- advisor findings.
--
-- 1. Three functions still had a mutable search_path. All three are SECURITY
--    INVOKER, so they run with the caller's own rights and were never an
--    escalation route the way the SECURITY DEFINER set was -- but a locked
--    search_path is free here: `update_last_edited_at` uses only
--    CURRENT_TIMESTAMP, `update_user_tracking` only auth.uid(), and
--    `expire_roles` already qualifies every table it touches.
--
-- 2. EXECUTE is withdrawn from the API roles on the functions that no caller
--    needs by name. Postgres checks EXECUTE on a trigger function when the
--    trigger is CREATEd, not when it fires, so the five trigger functions keep
--    working for ordinary inserts and updates.
--
--    Deliberately NOT revoked, because something genuinely calls them as the
--    signed-in user:
--      * can_view_org, can_edit_org, org_id_for_legal, user_has_permission
--        -- invoked by the RLS policies themselves, as the invoking role.
--      * generate_unique_slug  -- supabase.rpc() in routes/organisations/+page.server.ts
--      * user_max_role_level   -- supabase.rpc() in lib/server/authorization.ts

alter function community_orgs.update_last_edited_at() set search_path = '';
alter function community_orgs.update_user_tracking() set search_path = '';
alter function community_orgs.expire_roles() set search_path = '';

revoke execute on function community_orgs.update_last_edited_at() from public, anon, authenticated;
revoke execute on function community_orgs.update_user_tracking() from public, anon, authenticated;
revoke execute on function community_orgs.check_slug_not_reserved() from public, anon, authenticated;
revoke execute on function community_orgs.grant_owner_on_organisation_insert() from public, anon, authenticated;
revoke execute on function community_orgs.set_organisation_slug() from public, anon, authenticated;

-- Maintenance routine, no call sites in src/. service_role keeps its grant.
revoke execute on function community_orgs.expire_roles() from public, anon, authenticated;
