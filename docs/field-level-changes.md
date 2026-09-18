# P15 — field-level change reports

Complete locally, 18 September 2026. Migration, report generation and access
regressions pass. Hosted deployment and signed-in verification remain pending.

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

Database validation passed with all 38 unmodified migrations, 18 SQL suites,
CSV integration and concurrent identity/owner tests. Docker was unresponsive,
so the same repository harness ran through a temporary command adapter against
PostgreSQL 18.6 / PostGIS 3.6.2 extracted under `/tmp/p15-postgres`, with a private
Unix socket, no TCP listener and UTC (matching the ordinary test environment).
No system packages were installed. The adapter is retained at
`/tmp/p15-pg-bin/docker`; while those temporary files exist, reproduce with
`PATH=/tmp/p15-pg-bin:$PATH python3 scripts/test-operator-access-db.py`.
Each database instance was removed by the harness. The ordinary Docker
PostgreSQL 17 run remains unverified in this session. After Docker was confirmed
running, two further attempts still timed out during container creation after
60 seconds, before any migrations ran. The daemon answered version and cached
PostGIS image queries, but container listing also timed out. This is a container
startup blocker; the PostgreSQL 18 validation above remains the completed run.

The synthetic cohort report contained one new, one unchanged, one changed, two
conflicting (manual protection and branch identity hold), one rejected and one
missing record. Repeat reads were identical; after the changed fixture was
published, its report became unchanged and retained the publication ID and
approved field revision. All fixture writes rolled back.

Apply
[`20260918040000_ingestion_change_report.sql`](../supabase/migrations/20260918040000_ingestion_change_report.sql)
after the existing P14 migration, then deploy the portal route and download
control. Verify an actual operator download and non-operator denial before pilot
use. No hosted migration, deployment, real source enablement or publication has
been performed for P15. Existing approval and publication functions are unchanged.
On a report defect, remove the download control or revoke the new RPC and apply a
forward repair; there is no report-owned persistent data to roll back.
