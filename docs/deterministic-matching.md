# P14 — deterministic identity matching

Complete and deployed, 18 September 2026. Hosted inventory, unverified legacy
backfill reconciliation, migration, production deployment and signed-in access/MFA
verification passed. No real identifier was promoted to verified ownership by
this rollout; [P16 implements exact-ABN acquisition](exact-abn-lookup.md);
authenticated live qualification remains pending.

## Behavior

The private identity model adds reviewed organisation classifications (default
`unknown`), competing identifier claims, canonical identifier reservations,
classification/holder/link audit and evidenced, dated branch-parent links.
Existing organisation UUIDs and public legal/contact values are preserved.
Legacy values are copied idempotently using legal-row ID, field and value hash;
ABNs receive checksum validation but remain **unverified**. Incorporation values
without jurisdiction remain unresolved. Every legacy legal row is retained.

The review queue shows `match`, `hold` or `review` and the reason. Its first
candidate and default comparison target use an existing source link, otherwise
an exact verified ABN, otherwise a verified NSW incorporation key. Names and
unverified display identifiers remain suggestions. Matching never saves a review,
creates an organisation or publishes anything automatically.

All strong identifiers are considered together. Different holders, disputed or
withdrawn reservations, a changed ABN on a published source identity, or conflicting
branch/service scope produce a hold. Link/create review, approval and publication
recheck the result in SQL. Defer/reject remain available. A new source resource has
its own native-ID namespace; `_id` alone never crosses resources.

ABNs allow ASCII digits and display spaces, and must pass the checksum before
verification. NSW incorporation numbers preserve case, punctuation and leading
zeros; `NSW` maps explicitly to `AU-NSW`. ACN matching and other jurisdictions
remain disabled pending their qualified normalizers. Registry status is retained
in evidence independently of ownership; cancellation does not release a key.

One scoped key has one reserved holder. One legal entity has at most one active
verified ABN. A competing reviewed claim is retained as disputed evidence, marks
the reservation disputed, and returns `conflict`; it does not transfer the holder.
A stale concurrent submission returns SQLSTATE `40001` and must be re-read.
Changed, cleared or removed legal identifiers dispute the affected verified
keys; writing the same accepted value or changing ABN display spaces does not.
Restoring matching requires another evidenced operator review.

Classification, identifier and branch review are operator/MFA-protected RPCs;
workers and organisation editors cannot call them. Evidence and audit have no
browser table grants. Branch-parent intervals may not overlap; parents must be
legal entities and children branches, which also prevents cycles. Historical
branch relationships constrain reclassification.

Source links now have exactly one organisation or service foreign key. Existing
organisation links retain their target. Service and branch **publication remains
held** until their dedicated review/publication paths exist. Existing reviewed
organisation creation can still produce an `unknown` organisation; it cannot own
a canonical identifier until explicitly classified as a legal entity. This keeps
the established no-identifier group workflow without inferring legal status.

## Operator evidence review

Use `community_orgs.ingestion_identity_inventory()` through an authenticated
operator session to read current classifications, key revisions, claims and branch
links. This pilot inventory is unpaginated and private. The portal queue displays
matching results; identity maintenance currently uses these RPCs rather than a new
browser form:

- `review_entity_identity(p_org, p_revision, p_kind, p_evidence)` accepts
  `unknown`, `legal_entity`, `community_group` or `branch` and an evidence object
  containing a nonempty `reference`. Initial classification revision is 1.
- `review_identifier_identity(p_org, p_scheme, p_jurisdiction, p_value,
p_revision, p_state, p_evidence)` uses revision 0 for a new key; otherwise use
  its current revision. States are `verified`, `disputed`, `withdrawn`.
  Evidence requires `reference`, `authority`, `holder_name`, RFC3339 `observed_at`
  and `qualified_registry_review: true`. This is an explicit operator attestation
  that qualified registry evidence binds that exact key to the reviewed entity;
  it is not an automated lookup or a licence approval. Include native registry
  status and effective dates as additional evidence properties when supplied.
- `review_branch_identity(p_branch, p_parent, p_from, p_until, p_evidence)` records
  an evidenced parent interval; `p_until` may be null. Evidence needs `reference`.

Never use synthetic test evidence for real verification. Failed or unavailable
lookup evidence can stay in staged assertions without creating an accepted key.
An incorrect holder reservation needs a separately reviewed database forward
repair; the ordinary verifier intentionally cannot reassign it to another entity.

## Approval and concurrency behavior

Approval captures a private identity revision. Publication takes the same portal
lock as identity review, verifies that revision, rechecks the match and then calls
the existing field/publication engine. Identity changes invalidate pending
approvals, including approvals made before this migration. Completed publication
retries retain existing suppression checks and reuse the original target.

The revision is deliberately global for the bounded pilot. Even an unrelated
classification, organisation creation or source-link change can require a fresh
approval. Approve and publish one record at a time. This trades throughput for
simple, conservative concurrency safety; finer per-identity revisions can follow
measured operator need. Field protection, visibility, suppression and importer
ownership controls continue through the existing publication implementation.

## Deployment and recovery

1. Run [the read-only preflight](../scripts/identity-inventory.sql) privately on the
   target database **before** applying the migration. Retain the report privately;
   it includes identifiers. Review multiple legal rows, collisions, unscoped
   incorporation values, source links and possible branch/service entities.
2. Apply [the additive migration](../supabase/migrations/20260918021340_deterministic_identity.sql).
   It backfills evidence only; no legacy entity is classified or verified.
3. Compare pre/post UUIDs and relationship, role, service, publication, suppression
   and source-link counts. Review the resulting unverified claims and resolve real
   collisions through recorded evidence before populating canonical holders.
4. Deploy the queue/type changes and verify real signed-in operator/MFA boundaries,
   a conflict hold, fresh approval and replay. Reapprove outstanding change sets.
   Do not release branch/service holds or enable schedules as part of this rollout.

On a defect, pause publication and keep acquisition/staging evidence. Do not expose
the revoked `*_before_identity` functions as a bypass. Prefer an additive forward
repair with expected revisions and the same portal lock. Restore a prior
classification/key/link only after checking intervening audit, canonical uniqueness,
branch history and stale approvals; audit triggers retain before/after values.
Never drop claims/audit, rekey organisations, merge suspected duplicates or clear
manual protections to repair identity. A deliberate holder correction must record
its authority, reason and previous reservation in the audit transaction.

## Validation

`python3 scripts/test-operator-access-db.py` runs 37 unmodified migrations in
isolated PostGIS 17 (no host ports or hosted credentials), 17 SQL suites, CSV
integration, concurrent identity claims and concurrent owner revocation.
The P14 suite covers normalization/checksums, legacy multi-row/shared-ABN backfill
and replay, unverified suggestions, canonical ABN and scoped incorporation matches,
leading zeros/jurisdiction separation, conflicting strong IDs despite an existing
link, native-ID identity changes, branch/service holds, one active ABN, reservation
retention, manual-edit disputes, stale classification approval, publication replay,
exclusive service targets, denied access and conditional MFA. The concurrency test
confirms one holder, stale-contender refusal and a durable conflict on reviewed retry.

Svelte check, review-route regression, targeted ESLint and production build pass.
The SQL acceptance fixture also supports rollback-only hosted verification:
`supabase/tests/deterministic_identity.sql` supplies a synthetic auth email and
scopes identity assertions to its fixture organisations. It never commits fixtures.

The build retains existing Rollup annotation/chunk warnings. These are local
results with emulated auth/JWT scaffolding. The separate hosted evidence below
uses the real schema and actual signed-in sessions.

## Hosted completion — 18 September 2026

The user explicitly approved the private inventory, P14 migration, portal
production deployment and temporary verification fixtures. Applied the migration
through the connected Supabase MCP server to `gqltsfijginclwszrcfj` as
**20260918021340**; the repository filename matches the hosted version.

The reviewed inventory contained seven organisations, seven legal rows, seven
source links, eight publications and one suppression. There were no organisation
role assignments, relationships or services, no duplicate normalized ABNs, no
multiple legal rows per organisation, no incorporation numbers and no mismatch
between linked source ABN assertions and legacy ABNs. All seven UUIDs and links
were preserved. Pre/post/final fingerprints of organisations, legal rows, roles,
relationships, services, publications, suppressions and source links were equal.
Restricted inventory files are retained locally under
`/tmp/p14-deployment-20260918/`; no private identifiers are added to this report.

**Reconciliation decision:** retain all seven legacy assertions as unverified.
Six real ABNs passed checksum validation; the pre-existing synthetic all-zero ABN
is invalid. All seven classifications remain `unknown`; canonical holders remain
empty because this rollout did not accept qualified holder/classification evidence.
This is the completed conservative legacy-backfill decision, not automatic
verification or a merge. Existing source-link matching is active. Verified-key
matching was demonstrated using temporary synthetic evidence in the rolled-back
acceptance transaction. Future qualified verification proceeds through the operator
RPCs/P16 without another schema rollout. The decision and validation summary are
retained in private `ingestion.identity_events` as `deployment_reconciliation`,
with a null actor for the explicitly approved system operation rather than an
impersonated human account. No outstanding unpublished approval required renewal.

The complete [P14 SQL suite](../supabase/tests/deterministic_identity.sql) passed
on hosted Supabase with rollback. Its MFA fixture now supplies an explicit UUID
and timestamps required by the hosted auth schema. This covers matching, conflict
holds, checksum validation, classification changes invalidating approvals, fresh
approval/publication/replay, reservations, private grants and conditional MFA.
All synthetic rows rolled back; identity sequences may have advanced.

Production deployment **dpl_B3vfvNpga76joKAEiyK5rery8wwW** is READY and aliased to
[community-orgs-portal.vercel.app](https://community-orgs-portal.vercel.app).
Using two temporary registered accounts, the
[hosted verification script](../scripts/verify-p14-hosted.mjs) verified:

- Public organisation listing returns 200; signed-out ingestion requests redirect.
- A registered non-operator receives HTTP 403 and RPC SQLSTATE `42501`.
- An appointed operator sees the production identity-match UI and existing source
  link on run 12/version 18, and can read the private inventory.
- A real TOTP enrollment and verification denies the retained AAL1 token while
  allowing AAL2 inventory RPC and production queue access.

This is real signed-in HTTP/RPC testing, not a new interactive browser/form test.
The script's explicit `prepare`, `test` and `cleanup` modes target this project's
current seven-record pilot; `prepare` writes credentials only to a mode-0600 local
file. Grant its printed operator account the temporary ingestion appointment
before `test`. `cleanup` removes both accounts, sessions and factors; the operator
appointment cascades. All temporary accounts/appointments were removed and the
credential file deleted. No synthetic source or organisation remains.

Regenerated hosted `community_orgs,public` TypeScript types with the CLI and
synchronized the four P14 public RPC contracts (the MCP generator exposes only
`public`). Local Svelte check and route regressions pass with these contracts.
The Vercel deployment contains the runtime changes; subsequent repository changes
are verification scripts, types and this completion record. Preserve the working
tree in Git before a later Git-triggered deployment.

Scheduling remains Off (`interval_hours` and `next_due_at` are null). No real
publication, source enablement, suppression, field correction or canonical
verification was performed. Branch/service publication and P16 remain separate.
