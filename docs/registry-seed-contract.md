# Registry seed candidate contract (P31)

Status: implemented locally on 22 September 2026. The migration is not recorded as
deployed to the hosted database.

P31 separates broad registry discovery from the existing reviewed ingestion and
publication workflow. An ABN bulk record or NSW search result is a private
candidate. Its presence does not establish community relevance, local service
delivery, identity equivalence or permission to publish.

## Storage boundary

Migration
[`20260922010000_registry_seed_candidates.sql`](../supabase/migrations/20260922010000_registry_seed_candidates.sql)
adds these private `ingestion` tables:

| Table                                                  | Purpose                                                                                                  |
| ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| `registry_seed_releases`                               | Immutable release key, manifest/content hashes, configured scope, actual completion and retention policy |
| `registry_seed_release_parts`                          | Complete inventory of expected files or result pages, including status, hashes and counts                |
| `registry_seed_candidates`                             | Stable provider identity keyed by source, resource and native identifier                                 |
| `registry_seed_candidate_versions`                     | Deduplicated raw evidence and mapped assertions                                                          |
| `registry_seed_release_candidates`                     | Version membership, in-scope flag and explicit selection reasons                                         |
| `registry_seed_triage` / `registry_seed_triage_events` | Current revision-fenced decision and immutable decision history                                          |
| `registry_seed_promotions`                             | Audit link from a candidate version to the ordinary private ingestion run/version                        |
| `registry_seed_retention_events`                       | Raw-evidence expiry previews and applications                                                            |

All tables have RLS enabled and no browser-role policies. Browser roles and the
service role have no direct schema/table access. `ingestion_worker` can call only
the staging function; an authenticated ingestion operator can triage and promote;
only a platform administrator can apply candidate raw-evidence expiry.

No P31 function inserts or updates `community_orgs` tables.

## Release envelope

`ingestion.stage_registry_seed(manifest, candidates)` accepts contract version
`registry-seed-v1`. A manifest must contain:

- one enabled `(source_id, resource_id)` and immutable `release_id`;
- parser version and observation timestamp;
- `complete`, `partial` or `failed` actual completion;
- a scope with `kind`, `snapshot_series`, `complete_snapshot` and the configured
  `selection` (for example postcodes and explicitly known ABNs);
- every expected part/page with a unique ordinal and key;
- a verified SHA-256 and record count for every completed part;
- an error inventory; and
- either a reasoned indefinite `hold` or a future, reasoned `scheduled` raw expiry.

A `complete` release requires every declared part to be complete, no errors and
`scope.complete_snapshot=true`. Partial/failed releases must expose a failed part
or error and cannot be promoted. Here, “complete snapshot” means complete for the
declared configured scope. It is not a claim that the candidate subset is the
whole national register.

The database hashes both the manifest and ordered candidate array. Replaying the
same release is idempotent; reusing its key with changed content is rejected.
Candidates require a stable native identifier, raw object, unique mapped assertion
fields, and one or more selection reasons. Both in-scope and adjacent/out-of-scope
candidates may be retained so the selection can be audited.

## Triage and promotion

The current candidate states are:

- `pending`: no triage row yet;
- `include`: eligible for bounded promotion;
- `exclude`: not in the configured cohort;
- `defer`: insufficient evidence or a later decision is required; and
- `link`: include with exactly one explicit candidate or existing source-record
  target. P35 will add the user-facing cross-source resolution workflow.

`save_registry_seed_triage` uses an expected revision, a required note and an
immutable event record. Stale writes fail rather than overwriting another review.

`promote_registry_seed_candidates` accepts at most 500 versions. Every version
must belong to the selected complete release, be in scope, and have an `include`
or `link` decision. It creates an idempotent `ingestion.ingestion_runs` entry plus
ordinary source records, versions and assertions. The run remains
`publication_eligible=false`; existing matching, field review and publication are
still mandatory. The promoted scope is deliberately marked non-complete so a
bounded promotion can never drive absence reconciliation for the source release.

## Retention

Each release carries a retention policy:

- `hold`: raw evidence remains until the policy is changed; or
- `scheduled`: `raw_expires_at` must be in the future when staged.

`expire_registry_seed_raw` previews or applies an expired scheduled policy. It
removes only candidate raw payloads, retains mapped assertions and audit metadata,
does not remove a version still protected by another release, and records every
preview/application. A release whose raw evidence has been removed cannot be
promoted. Provider withdrawal/redaction across promoted copies remains part of
P36 validation before recurring collection is enabled.

## Validation

[`registry_seed_candidates.sql`](../supabase/tests/registry_seed_candidates.sql)
passed against PostgreSQL 17 in a disposable database. It covers:

- private grants and RLS on every candidate table;
- complete multipart inventory and immutable/idempotent replay;
- changed-replay rejection;
- revision-fenced include/exclude triage;
- successful bounded promotion into existing private reviewed staging;
- proof that promotion creates no organisation;
- rejection of excluded/out-of-scope and partial-release promotion; and
- administrator-only, audited raw-evidence expiry.

P33 and P34 can now implement their adapters against this boundary. P32 remains
required before the larger cohort is published, but it does not block private
candidate acquisition.
