# P09 — private ingestion storage and raw retention

Implemented locally: 17 September 2026. Hosted migration and verification pending.

P09 builds on the deployed staging/review/publication schema rather than introducing
another store. Migration
[`20260917071152_private_raw_retention.sql`](../supabase/migrations/20260917071152_private_raw_retention.sql)
adds source-scoped raw snapshot retention, preview/removal and removal audit.
It seeds no policy, removes no evidence and changes no source, schedule or public data.

## Storage contract

| Requirement | Implementation |
| --- | --- |
| Qualified sources | `ingestion.sources`, source approval revisions/events; disabled by default |
| Runs and observations | `ingestion_runs`, `run_records`; complete/partial/failed status, original observation and staging times |
| Source identities and versions | `source_records`, `source_record_versions`; identity is scoped to source **and resource** and native ID; parser/content hash deduplication |
| Links and assertions | `source_links`, `field_assertions`; reviewed target links and typed values |
| Review/change sets | `reviews`, `review_events`, immutable `change_sets`, `publications` |
| Private raw objects | JSONB run envelopes, version payload `raw` objects and acquisition checkpoints |
| Source retention | `raw_retention_policies`, `raw_retention_events`, removal timestamps and original envelope hashes |

For the bounded pilot, raw objects remain in PostgreSQL JSONB. This is a deliberate
implementation choice in place of the strategy's proposed external object bucket:
it keeps acquisition, checkpoint recovery and retention transactional. No public
bucket, URL or download credential is introduced. A separate private object-store
adapter remains a scaling option before bulk/national ingestion, not a prerequisite
for the bounded pilot. Existing Python/offline JSON files are outside this database
retention boundary and must be managed separately.

The ingestion schema remains outside PostgREST's exposed schemas. Every private
table has RLS and no browser policies. Anonymous, authenticated, service and worker
roles have no direct access to these tables. The worker can call narrow acquisition
and staging functions; it cannot bypass the retention-aware staging entry point or
run cleanup. Existing operator RPCs provide authorised review access, including raw
evidence while retained. Organisation roles do not confer ingestion access.

Staging does not create organisations, publish data or grant ownership. Publication
and normal organisation creation keep their existing, separately tested behaviour.
Existing organisation UUIDs and relationships are untouched.

## Retention semantics

A database administrator records a reviewed policy for each `(source_id, resource_id)`.
A missing policy or `hold = true` retains all evidence. The migration intentionally
does not invent retention periods or remove existing evidence. `retain_days` must
be 1–36,500; `reason` records the policy basis. This is an operational raw snapshot
policy, not a claim about provider permission or a complete erasure mechanism.

Eligibility is calculated at maintenance time using the database clock:

- Run envelopes expire after `retain_days` from **staging**, including failed and
  partial runs. Removal clears accepted record copies, quarantine and error details;
  original counts, run metadata and the original envelope SHA-256 remain.
- A version's raw object expires only when **all** its run observations are old
  enough. A fresh observation extends the shared object's lifetime. Typed assertions,
  assertion source values, mapping metadata and content hashes remain for review,
  attribution and publication audit. The payload records `raw_evidence_removed`.
- Terminal acquisition checkpoints expire after the same period from `finished_at`,
  including cancelled/failed jobs without a staged run. Jobs lacking a finish time
  remain retained for administrative investigation.
- Any queued/running job for the source holds cleanup, preserving crash recovery.
  Holds and cleanup are serialized against acquisition/staging writes. The pilot
  implementation uses table locks; run maintenance during a quiet period.

Preview is the default. Explicit application removes all eligible copies in one
transaction and records counts, the policy snapshot, timestamp and database actor.
Repeated cleanup with no eligible rows produces no extra audit entry. No cleanup
schedule is enabled; administrators must arrange execution under the approved policy.

The original run key remains immutable after removal: identical replay returns the
same run ID; changed content is refused. Reusing an expired semantic version does
not restore its raw object or duplicate it. A new acquisition run can retain its
own new envelope until its deadline. Retention does not alter assertions, approved
changes, source links, publication events, suppression or public organisations.
Reprocessing an expired raw snapshot is no longer supported; acquire fresh evidence
instead. Backups, exported files and downstream copies require separate lifecycle
management. Provider-mandated deletion of assertions/audit content needs a dedicated
erasure operation; this raw snapshot policy must not be used as a substitute.

## Administrative procedure

First apply the migration to an explicitly selected database. Verify that `ingestion`
is not in exposed API schemas and review the source policy before configuring it.
Use an administrative database connection, never browser or worker credentials.
The example source/resource and period below are placeholders, not an approved ACNC
retention decision:

```sql
insert into ingestion.raw_retention_policies
  (source_id, resource_id, retain_days, hold, reason)
values ('<source>', '<resource>', 90, true, '<reviewed policy reference>');

-- Release the hold only after the source-specific policy has been approved.
update ingestion.raw_retention_policies set hold = false, updated_at = now()
where source_id = '<source>' and resource_id = '<resource>';

-- Preview makes no changes. Apply recomputes eligibility under the same locks.
select ingestion.expire_raw_evidence('<source>', '<resource>');
select ingestion.expire_raw_evidence('<source>', '<resource>', true);

select * from ingestion.raw_retention_events order by id desc;
```

No HTTP RPC, UI, worker permission or public database type is added for maintenance.
Policy changes are privileged administrative operations; record their approval in the
operational change log. Each actual removal retains the exact policy used.

## Validation and deployment

`npm run test:operator-access:db` applies 35 unmodified portal/access/ingestion
migrations to a disposable PostGIS 17 database. Eight SQL suites include P09 private
privileges/RLS, missing-policy/default holds, preview, active checkpoints, terminal
checkpoint expiry, shared-version retention, raw-copy removal, preservation of
assertions, immutable replay after expiry, no rehydration, audit and no publication.
Existing publication tests cover public defaults and imported owner-grant prevention;
organisation permission and concurrent owner-revocation tests also pass.

The Python ingestion suite passes all 51 tests. The SQL fixture generator includes
P09. The full ingestion SQL suites and real worker recovery checks passed in
disposable PostgreSQL 16: interruption before/after checkpoint, manual-edit and
withdrawal protection, and failed/partial acquisitions. Auth/JWT
helpers in disposable databases are emulated; these checks are not hosted verification.

For deployment, apply the migration and run the rollback-only
[`private_raw_retention.sql`](../supabase/tests/private_raw_retention.sql) against the
selected hosted database. Check the restricted worker can still stage and that no
retention policy was implicitly seeded. No application deployment is needed for
these database-only additions. Hosted closure remains pending.

Forward repair: leave all policies held while investigating; fix functions in a
new migration while preserving run IDs and original hashes. The schema migration
itself does not delete evidence. Once cleanup is committed, removed raw objects
cannot be recovered by rolling back DDL. Restore only from an authorised retained
backup into an isolated database, subject to the source policy. Do not restore the
old staging function after cleanup: it compares full envelopes and cannot recognise
expired-run replay. Do not drop the retention timestamps, hashes or audit history.
