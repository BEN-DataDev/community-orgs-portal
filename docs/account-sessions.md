# Account sessions

Account → Security → Devices & sessions lists the signed-in account's Supabase Auth sessions and marks the current session. Users can refresh the list, revoke an individual other session, sign out other sessions, or confirm signing out everywhere. Ordinary sign-out now uses the `local` scope so it leaves other sessions signed in.

Browser and operating-system labels are inferred from the recorded user agent; server-side sign-ins often record `node`, so the UI explicitly reports unavailable browser details. Dates use UTC. “Last refreshed” is a token-refresh time, not activity or online status. No IP address, location lookup, or additional device tracking is added. The newest 100 unexpired sessions are shown, with the current session first and the full count when truncated. Bulk sign-out covers all sessions.

## Security and database dependency

The `account_session_management` migration adds narrow `community_orgs` RPCs. Both listing and individual revocation require a permanent account, an existing owned current session, and AAL2 when MFA is enrolled. Only the authenticated role may call them. The internal access-check helper cannot be called directly by clients. Queries filter by `auth.uid()`, exclude sessions past `not_after`, and never return access tokens, refresh tokens, IPs, or session secrets. The security page disables caching.

Supabase's installed SDK supports `local`, `others`, and `global` logout scopes, but no per-session-ID logout. Individual revocation deletes only the requested owned row from `auth.sessions`; the existing Auth foreign key cascades to `auth.refresh_tokens`, matching the database effect of Auth logout. The current session must use the normal Auth sign-out flow so browser cookies are cleared. This implementation depends on Supabase-managed Auth table columns and the refresh-token cascade: rerun the SQL and live tests when upgrading Auth. It makes no Auth schema changes and does not use the unrelated legacy `public.sessions` table.

Revocation prevents renewal. Previously issued access tokens can remain usable until expiry; the UI states this limitation. These controls do not implement immediate revocation checks on every application/API request or change JWT expiry configuration.

## Verification

- `npm run test:sessions`: server action validation, access/MFA guards, exact logout scopes, failure states, redirects, and safe browser labels.
- `supabase/tests/account_sessions.sql`: run as postgres; rollback-only fixtures check ownership, refresh-token cascading, current-session protection, invalid/guest/expired callers, MFA, list limits and grants.
- Live browser verification uses a disposable confirmed account and multiple password sessions. Check individual, other, local, and global sign-out by attempting refresh of each affected session. Delete the test account afterwards. No emails need to be sent.

Supabase references: [sessions](https://supabase.com/docs/guides/auth/sessions), [sign-out scopes](https://supabase.com/docs/guides/auth/signout).
