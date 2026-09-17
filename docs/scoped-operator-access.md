# P07 scoped operator access

Implemented and deployed: 17 September 2026. Hosted migration
`20260917063242_scoped_access_expiry.sql` and the production application are live.
This implements and verifies the [P06 capability matrix](capability-matrix.md) global access boundary;
P08 organisation role-management UI and ownership safeguards remain separate.

## Result

Organisation membership, including admin/owner, grants no global ingestion or
platform administration capability. Operators can use import review and acquisition
jobs; source enablement and acquisition configuration require a platform
administrator. The administrator capability includes operator authority and effective
owner access across organisations. The existing database appointment checks remain
the authority, including conditional MFA and immediate appointment revocation.

[Shared server gate](../src/lib/server/admin-access.ts) now serves the request hook
and the Admin hub loader. The hub independently checks access and returns
`Cache-Control: private, no-store`. Each review, source and job loader/action retains
its own capability check. Failures or non-boolean capability responses cannot grant
access. Unknown tasks beneath `/admin/` require a platform administrator; matching
the ingestion prefix requires the exact path segment.

Database testing uncovered an expired-role read leak: the baseline's permissive
organisation SELECT policy checked `is_active` but not `expires_at`. Even though
server and child-table helpers ignored the expired assignment, direct organisation
reads could still succeed. The [new migration](../supabase/migrations/20260917063242_scoped_access_expiry.sql)
replaces that policy with `can_view_org(org_id)`, preserving the established public,
active membership and platform-admin rules. Existing creator reads remain an
independent policy: the creator can still read the base organisation row after role
revocation. That does not confer editing, child-record or global access.

The older P2 regression now explicitly verifies that the organisation membership
lookup does not imply either global capability. No appointment schema or new
permission hierarchy is introduced.

## Verification

| Check | Evidence and scope |
| --- | --- |
| `npm run test:operator-access` | Every current Admin loader/action denies absent, failed or malformed capability results before reading data or parsing mutations; shared gate tests hub, ingestion, job, source, trailing-slash and unknown task paths; operator/admin split and session reuse after revocation |
| `npm run test:operator-access:db` | Disposable PostGIS 17 database, 33 unmodified portal/access/ingestion migrations, five rollback-only SQL suites: P2 organisation/global distinction, platform administrators, P07 operator access, ingestion review and publication |
| Database negative cases | No assignment, member, moderator, admin, owner, expired and inactive assignments across two private organisations; all 14 exposed review/job/source read and mutation RPCs deny organisation-only actors; private schema table/function grants remain closed |
| Database positive cases | Active organisation reads/edits retain their scope; operators read review/jobs and enqueue; administrators enable sources and configure jobs with correct actor audit records; existing review/publication suites verify matching, immutable approval, replay, manual-edit protection and no imported owner grant |
| Session cases | Real `user_has_verified_mfa()` reads fixture factor rows; enrolled AAL1/missing AAL denied, AAL2 allowed, unenrolled AAL1 allowed; anonymous/no-subject denied; revoked appointments lose global authority while a separate organisation assignment remains valid |
| Existing application regressions | `test-platform-admin.mjs`, `test-ingestion-review.mjs`, `test-source-approvals.mjs`, `test-acquisition-jobs.mjs` pass |
| Static/build validation | Svelte check (zero errors/warnings), targeted ESLint and production build pass; build emits Rollup annotation and Sharp optional-dependency warnings |

The [database runner](../scripts/test-operator-access-db.py) uses the locally cached
`postgis/postgis:17-3.5` image, no network, ports, mounts, credentials or external
URLs, and removes its container. It emulates only auth users/factors and JWT helper
functions; organisation RLS and capability functions come from real migrations.
Unrelated account storage/session, orphan-public-table and hosted-extension
migrations are explicitly excluded. This is not a hosted Supabase or browser-login
verification. No production source, job, schedule, appointment or publication changed.

## Deployment and hosted verification — 17 September 2026

- Applied `scoped_access_expiry` as hosted migration **20260917063242** to
  `gqltsfijginclwszrcfj`. Verified the installed policy calls
  `community_orgs.can_view_org(org_id)`. Renamed the local migration to match the
  hosted version, avoiding new migration-history drift. No API signatures changed.
- Deployed the authorised working tree with Vercel CLI to the existing project.
  Deployment **dpl_9PPf4QrDxtVqyMYN7zQjB9bzDQZt** is READY and aliased to
  [the production portal](https://community-orgs-portal.vercel.app).
- Ran the P07 SQL suite against hosted Supabase in a rollback-only transaction.
  The only fixture adaptations supply timestamps/email for the real user-profile
  trigger and required ID/type/timestamps for the real MFA factor table. Role
  scope, all 14 global RPC denials, private grants, conditional MFA, source/job
  permissions, actor audit records and appointment revocation passed. Verified
  zero retained SQL test users, organisations or sources.
- Used three temporary synthetic registered accounts for real signed-in HTTP
  checks. Public organisation browsing returned 200; signed-out Admin routes
  redirected to sign-in. Organisation-only owner access returned 403 on the hub,
  review, jobs and source pages. The operator received 200 on hub/review/jobs and
  403 on source administration. The administrator received 200 on all four pages.
  Successful Admin reads include private/no-store caching.
- Global mutation requests from the owner were denied with 403. Operator source
  changes/configuration were also denied. Permitted operator review/queue and
  administrator configuration/source actions rejected empty inputs with action
  failure status 400 (SvelteKit JSON envelopes use HTTP 200). No import, source
  change or publication was requested by those HTTP checks.

- Expired the test owner's assignment and revoked both temporary global
  appointments, then reused the existing authenticated sessions. All three were
  denied Admin and direct ingestion RPC access; PostgREST returned no private
  organisation row. This verifies revocation without signing out or refreshing
  credentials.
- Removed the temporary HTTP organisation, assignments and all three auth
  accounts; verified zero remaining fixture users, organisations or global
  appointments. The local session file was deleted. Pilot schedules remain Off.
  SQL fixture source/job actions were rolled back and no real publication changed.

P07 hosted closure is complete. This was a working-tree deployment; these changes
remain uncommitted and must be preserved before a future Git-triggered deployment.

## Repair

The policy migration changes no stored data and can be applied while the prior
application runs. If application rollback is needed, retain the database expiry
fix. Forward repair should restore the same helper-based policy rather than
reintroducing the expired-assignment SELECT branch. Platform appointment grants
and revocations remain controlled, recorded deployment operations as specified
in P06; this work does not add appointment-management UI.
