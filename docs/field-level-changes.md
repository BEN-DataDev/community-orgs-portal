# P15 — field-level change reports

Complete and deployed, 18 September 2026. Local and hosted SQL verification,
production downloads, operator access and real MFA checks pass.

The import review page offers **Download dry-run report** for the selected run.
Optionally enter an earlier baseline run ID. The JSON download contains private
source evidence and must be handled as operator data. The endpoint and database
RPC require ingestion operator access, including the existing conditional MFA
check. Responses use private/no-store caching and download disposition.

`community_orgs.ingestion_change_report(p_run, p_baseline)` returns `p15-v1`:

- Counts and records classified as `new`, `unchanged`, `changed`, `conflicting`,
  `rejected` or `missing`.
- Every existing mapped/unmapped field preview, including current and proposed
  values, original input, source values, protection, revision and mapping tokens.
- Current identity result and saved review, review history, retained source payload,
  parser and content hash, and the prior observation in the same scope. Prior
  observations use observation timestamps rather than version sequence numbers;
  unchanged acquisitions can reuse the same version.
- Per-field prior source assertions and publication history with approved
  revisions and exact saved changes. An absent `prior_source` is null, distinct
  from an explicit prior JSON-null assertion (`present: true, value: null`).
- Quarantined rows with retained reasons/evidence, run errors, and an explicit
  indication when raw evidence has expired under the retention policy.

Record status precedence is saved rejection, identity/field conflict, new target,
changed mapped values, then unchanged mapped values. Invalid, ambiguous, protected
conflicting and suppressed fields make the record conflicting. An explicit create
review does not bypass a conflicting canonical identity. `new` means there is no
selected/matched portal target, even if this source version was seen before.
`unchanged` refers to mapped portal values; missing and unmapped assertions remain
visible and do not assert that all source evidence is identical. Deferred reviews
remain visible and are not approvals. The existing field statuses are preserved;
record categories never confer publication eligibility.

A baseline must be a strictly earlier observation with the same source, resource
and nonempty explicit scope. Different scopes/resources and equal or later
observation times are rejected. Missing-record assessment is disabled without a
baseline, for partial/failed runs, or after either run's raw evidence expires.
When assessed, `missing` means a baseline identity was not observed in this run.
This is useful even for a bounded CSV cohort; it does **not** imply absence from a
registry, cessation, deletion, suppression or withdrawal. Missing fields likewise
never become clears. Annual revenue retains its existing mapping and is not
converted into an annual budget.

The report is a read-only view of current portal/review state, ordered
reproducibly for unchanged database state. It is not an immutable approval and
will change after an edit, review, publication, identity decision or retention
operation. It never creates organisations, approvals, links or publications.
The existing field approval snapshot contract is untouched. Reports are
unpaginated for the bounded pilot, like the existing reprocessing report; broader
cohorts need measured pagination/export limits before adoption.

## Validation and rollout

The SQL acceptance suite is
[`ingestion_change_report.sql`](../supabase/tests/ingestion_change_report.sql),
registered in `python3 scripts/test-operator-access-db.py`. It covers all six
categories, identity holds, prior observations/revisions, publication history,
unchanged replay, missing fields, incomplete runs, scope mismatch, retained
quarantine, expired evidence, access denial and absence of report writes.

Local Svelte check, the report endpoint regression, existing review-route tests,
targeted ESLint and production build pass. The build retains existing Rollup and
optional Sharp dependency warnings.

Database validation passed using the standard Docker PostgreSQL 17 / PostGIS 3.5
harness: all 38 unmodified migrations, 18 SQL suites, CSV integration and both
concurrent identity/owner tests passed. Run with
`python3 scripts/test-operator-access-db.py`. The disposable container was removed
by the harness; no hosted database was changed.

The same suite also passed on an isolated PostgreSQL 18.6 / PostGIS 3.6.2 instance
under `/tmp` while Docker container operations were stalled. Docker container
listing and creation now respond, and the successful standard run closes that
validation blocker.

The synthetic cohort report contained one new, one unchanged, one changed, two
conflicting (manual protection and branch identity hold), one rejected and one
missing record. Repeat reads were identical; after the changed fixture was
published, its report became unchanged and retained the publication ID and
approved field revision. All fixture writes rolled back.

## Hosted completion — 18 September 2026

Applied
[`20260918061301_ingestion_change_report.sql`](../supabase/migrations/20260918061301_ingestion_change_report.sql)
to Supabase project `gqltsfijginclwszrcfj`. The local migration filename matches
the hosted version. The P15 SQL acceptance suite passed on the hosted database
with rollback. Its auth fixture now supplies email and timestamps required by
the hosted profile trigger; the full local Docker suite passed again afterward.

Production deployment **dpl_5C1z4Yj78iktWmpsnJnZ3DcvuJua** is READY and aliased to
[community-orgs-portal.vercel.app](https://community-orgs-portal.vercel.app).
The [hosted verification script](../scripts/verify-p15-hosted.mjs) used two
temporary registered accounts to verify:

- Public listing returns 200; signed-out report requests redirect.
- A signed-in non-operator receives HTTP 403 and RPC SQLSTATE `42501`.
- An appointed operator can download the report from production, with
  `private, no-store` caching and the expected attachment filename. HTTP and RPC
  report contents agree, and the review page displays the download control.
- Invalid IDs and a same-run baseline return HTTP 400.
- Real TOTP enrollment/verification denies the retained AAL1 token and allows
  AAL2 report RPC and production download access.

Run 12 returned six records: one unchanged and five conflicting, with no new,
changed, rejected or missing records. No baseline was selected, so missing-record
assessment was explicitly disabled. Conflict reports are previews, not permission
to overwrite protected values. Private report payloads were not logged or committed.

All temporary accounts, appointments, sessions, MFA factors and the local
credential file were removed. No SQL fixture run remains. Organisation (7),
publication (8) and source-link (7) counts match the preflight. Scheduling remains
off. No real organisation publication, source enablement or identity verification
was performed. SQL fixture sequences may have advanced despite rollback.

The verification script has explicit `prepare`, `test` and `cleanup` modes.
`prepare` stores credentials only in a mode-0600 local file; appoint its printed
operator account before `test`. Always run `cleanup`, including after a failed
test. These are signed-in HTTP/RPC checks, not interactive browser tests.

The deployment contains the runtime changes. Subsequent local changes align the
migration filename, verification fixture and completion documentation. On a report
defect, remove the download control or revoke the new RPC and apply a forward
repair; there is no report-owned persistent data to roll back.
