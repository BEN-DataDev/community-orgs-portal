-- role_requests had RLS enabled with no policies, so it was deny-all for
-- everyone but service_role. That is safe, but it also broke the feature the
-- table exists for: a requester could not see their own request, and an admin
-- could not list the queue. It also made process_role_request unusable in
-- practice -- callers select the request id first, and that select returned
-- nothing.
--
-- Reads are opened here; writes deliberately are not.
--
-- No INSERT policy: requests are created through request_role(), which pins
-- user_id to auth.uid() and validates the org and role.
-- No UPDATE policy: status changes go through process_role_request(), which
-- checks the reviewer's permission, refuses an already-reviewed request, and
-- writes the audit row. A direct UPDATE would bypass all three.
--
-- reserved_slugs is deliberately left deny-all. Only check_slug_not_reserved()
-- reads it, and that is SECURITY DEFINER, so no API role needs a policy.

create policy "users can view their own role requests"
    on community_orgs.role_requests
    for select
    to authenticated
    using (user_id = auth.uid());

create policy "organisation admins can view role requests"
    on community_orgs.role_requests
    for select
    to authenticated
    using (community_orgs.can_edit_org(organisation_id));
