# Account avatars

The existing `public.users` row is authoritative for avatar preference. `avatar_url`
remains the signup snapshot of the OAuth image; `avatar_path` contains a private
Storage object path only when `avatar_source = 'upload'`. Removing the photo selects
`initials`, so a later OAuth login will not resurrect it. Linked authentication
methods share the same `auth.users.id` and therefore the same preference.

Uploads and provider imports go through the Settings server action with the user's
Supabase client (RLS applies). Inputs are limited to 2 MiB, JPEG/PNG/WebP, still
images, and 25 million pixels. Sharp auto-orients, strips metadata, resizes within
512 x 512, and encodes WebP. SVG and animated input are rejected. Provider imports
use Auth identity data and exact Google/GitHub/Discord image-host/path allowlists;
redirects, credentials, nonstandard ports, oversized responses and slow responses
are rejected. Microsoft photos requiring a Graph token are not imported; local
uploads work for Microsoft and all other permanent accounts.

`avatars` stays private. Owner read/insert/delete policies are constrained by a
restrictive policy requiring a permanent user and aal2 when MFA is enrolled. Avatar
URLs expire after 15 minutes; the root layout renews them one minute before expiry,
and on focus after a suspended tab wakes. Failed images fall back to initials.

Every upload uses `<user-id>/avatar-<uuid>.webp`. A compare-and-swap on
`avatar_revision` prevents stale forms overwriting newer choices. Old files are
removed only after the new profile reference commits. A definitive conflict deletes
the staged file. An ambiguous save/network error leaves it for cleanup because the
save may have committed.

The existing daily `/api/cron` job removes up to 100 unreferenced files older than
24 hours through the Storage API. Only the above managed filename pattern is
eligible; legacy files are preserved. Repeated runs drain any backlog. Cleanup
failures return a non-success status for the scheduled job. Live profile references
are excluded, including images imported from a provider.

Before introducing account deletion, remove that user's objects through the
Storage API **before** deleting the Auth user: Supabase can refuse deletion while
Storage objects are owned by the user. Existing account deletion is not exposed in
this app. Never delete rows from `storage.objects` to delete real files. The SQL
regression test uses synthetic metadata and rolls back its complete transaction.

The migration is `20260914223810_persistent_account_avatars.sql`. Generate database
types with `npm run update-db-types` (both `community_orgs` and `public`). Run
`npm run test:avatars`, `npm run test:cron`, `npm run check`, and `npm run build`.
Run `supabase/tests/account_avatars.sql` as postgres to exercise the live policies
with disposable fixtures; it does not retain users, profiles or Storage rows.
