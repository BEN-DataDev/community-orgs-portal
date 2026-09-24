# P08 organisation role management

Implemented, deployed and verified on 17 September 2026. Hosted migration
`20260917065322_organisation_role_management.sql` and the production application
are live; signed-in HTTP and direct-RPC verification passed.

## Workflow

Organisation managers open **Manage access** in the organisation section navigation
(`/organisations/[id]/access`). The page lists active, expired and revoked
assignments, account IDs, role names and expiry. Members, moderators, readers and
ingestion operators without a separate management assignment cannot open it.
Platform administrators can manage any existing organisation.

To grant a role, ask the registered account holder for their UUID from **Account
settings → My access**, then select an existing role within your hierarchy ceiling.
No global account/email directory is exposed. Grants have no expiry. Granting an
existing assignment reactivates it and clears its previous expiry; the form explains
this before submission. To revoke, confirm the specific assignment and optionally
record a reason. The page reloads its assignments after a successful action.
Database refusals and stale revocations are displayed instead of reporting success.

## Enforced rules

The new `organisation_role_assignments` RPC requires a registered session,
conditional MFA and `can_manage_members` for the exact organisation. It returns
only that organisation's assignment data and the actor's eligible role choices.
The loader and each action independently invoke it and fail closed on errors.
The page response is private and non-cacheable. Navigation visibility is only a
convenience; it uses the permission helper and does not grant access.

The existing `grant_user_role` and `revoke_user_role` RPCs remain the only browser
mutation path. They derive the actor from `auth.uid()` regardless of the legacy
actor argument. The route derives the organisation from its URL and supplies the
verified caller; submitted actor/organisation fields are ignored. Direct browser
INSERT/UPDATE/DELETE privileges on assignments are revoked.

Both RPCs lock the organisation row before resolving current actor/target scope,
serialising changes within an organisation. Grants now reject unregistered/guest
targets and changes to users ranked above the actor; revocation also checks the
assignment role itself, including expired assignments. Existing permission and
hierarchy checks remain. Repeated grants reuse the assignment; repeated revocations
return false and do not add another audit event. Successful changes audit the
actual caller; revocations retain the reason.

Ownership decisions for this minimum workflow:

- No actor, including a platform administrator, can revoke their own assignments.
  Another authorised manager must do so.
- New or renewed owner assignments cannot expire. Other RPC grants may specify a
  finite future expiry; the minimum UI grants without expiry.
- Revoking an active owner requires another account with an active, non-expiring
  owner assignment. A platform appointment alone does not satisfy that condition.
- Concurrent revocations are serialised, so two successful requests cannot remove
  both remaining owners. An ownership transfer grants the new owner first, then
  an authorised other account revokes the old owner.

These safeguards apply to this role-management workflow. They do not backfill
owners on imported organisations, repair existing expiring owners, or prevent
privileged database maintenance/auth-account deletion. An organisation without
owners can receive its first owner from a platform administrator. Custom role
definition changes, request/review UI and global appointments remain separate work.
Conditional MFA retains the existing policy: an enrolled actor must use AAL2;
an actor without a verified factor can use AAL1.

## Validation

- `npm run test:organisation-roles`: actual loader/action tests with synthetic
  Supabase responses cover denial before body/mutation, malformed responses, UUID
  validation, route/caller identity, RPC failures, confirmation and stale results.
  Svelte server rendering verifies grant/revoke forms, feedback and removal of
  ineligible revoke controls. This is not a browser/hosted end-to-end test.
- `npm run test:operator-access:db`: 34 unmodified migrations applied to disposable
  PostGIS 17, seven rollback-only SQL suites, and a two-connection concurrent owner
  revocation test. The P08 suite covers exact organisation scope, reader/member/
  moderator/operator/guest denial, hierarchy, expired/inactive authority, registered
  targets, replay, real audit identity, direct table writes, transfer and MFA.
  Existing P1/P2, platform, P07, review and publication suites pass. Auth users,
  factors and JWT helpers are emulated; the container is removed after testing.
- `npm run test:operator-access`, Svelte check (zero errors/warnings), targeted
  ESLint, Svelte autofixer and production build pass. Build emits existing Rollup
  annotation and optional Sharp dependency warnings.

## Deployment and repair

The deployed [migration](../supabase/migrations/20260917065322_organisation_role_management.sql)
provides the RPC required by the access page. The local filename matches the
hosted migration version. Existing production assignments were preserved.

If application deployment fails, the previous application can continue using the
existing RPC signatures with the stricter safeguards. Prefer a forward migration
for database repairs; do not restore unrestricted assignment writes or the old
last-owner behaviour. No production assignments are modified by this migration.

## Hosted verification — 17 September 2026

- Applied `organisation_role_management` as **20260917065322** to Supabase project
  `gqltsfijginclwszrcfj`. Verified the roster RPC is installed and authenticated
  clients lack direct assignment write privileges.
- The hosted P08 SQL suite passed in a rollback-only transaction. Fixture-only
  adaptations provided required user email/timestamps and MFA factor ID/type/
  timestamps. Scope, hierarchy, last-owner protection, conditional MFA, target
  validation, audit identity and direct-write denials passed. No SQL fixture
  accounts or organisations remained.
- Production deployment **dpl_HEtHzw9KTmdB8WZYj58qE7Xhv2eH** is READY and aliased to
  [the portal](https://community-orgs-portal.vercel.app). This was a working-tree
  CLI deployment; retain these changes in Git before a future Git-triggered release.
- Four temporary registered accounts and two private organisations exercised the
  real signed-in page and SvelteKit actions. Owner/admin reads succeeded with
  private/no-store caching; signed-out access redirected to sign-in; outsider and
  cross-organisation access were denied. Account settings displayed the caller's ID.
- Admin-to-owner grants and changes to a higher-ranked owner were refused. A valid
  admin grant appeared on reload and enabled the target's access. Replaying it
  retained one assignment. Revocation removed access using the same session and
  direct RPC; repeated revocation returned conflict status. Submitted actor/org
  fields could not alter the audit caller or route scope. Direct table writes failed.
- Enrolled and verified a real temporary TOTP factor. The retained AAL1 session
  could not access the page or roster/grant RPCs. The upgraded AAL2 session could
  load the page and grant/revoke roles. Test-session cookies were explicitly updated
  after MFA verification; no factor secrets or session tokens were logged.
- Owner self-revocation was refused. Granting another owner first allowed that new
  owner to revoke the old owner; the old owner's existing session immediately lost
  management access. Hosted SQL separately verified last-owner refusal.
- Removed all temporary assignments, synthetic audit rows, organisations and auth
  accounts (including the MFA factor). Cleanup respects the audit-log foreign key;
  final database inspection confirmed no retained P08 users, organisations or test
  audit rows. No pilot source, schedule, acquisition or publication was changed.

This closes P08. Verification used real signed-in HTTP/action requests and Supabase
sessions, including MFA, rather than interactive browser clicks. The earlier local
Svelte rendering and database/concurrency checks remain complementary evidence.
