# Portal establishment and governance gap analysis

Reviewed: 24 September 2026.

Target: [Portal establishment and governance](portal-establishment-and-governance.md).

## Executive assessment

The repository has a strong single-portal ingestion and organisation-access
foundation. Private source staging, validation, deterministic identity, reviewed
field publication, suppression, rollback, source approval, machine-worker fencing
and organisation role safeguards are already implemented.

The target architecture is nevertheless a material product and operational change.
The current system assumes one Supabase project, one global platform-administrator
set, one global ingestion-operator set and one combined import-review workspace. It
now has persisted singleton identity, lifecycle and authoritative scope history,
but has no stewardship state, invitation workflow, release-level separation of
duties, multi-source campaign, provider adapter or fleet operations capability.

The safest refactor is evolutionary. Preserve the existing ingestion evidence and
publication invariants while placing them inside explicit portal, campaign,
governance and operations boundaries. Do not begin by rewriting the ingestion
engine or adding `portal_id` to every table.

## Method and status meanings

This review compares the target design with checked-in routes, server helpers,
migrations, tests, configuration and operational documentation. It does not inspect
or change production state.

- **Implemented:** the current capability substantially satisfies the target.
- **Partial:** reusable implementation exists but the target contract is incomplete.
- **Missing:** no corresponding repository capability was found.
- **Conflicting:** current behaviour grants or couples authority differently from
  the approved target and must be changed deliberately.
- **Provider-bound:** implemented through Supabase or Vercel without an application
  provider boundary.

## Capability summary

| Area                                | Status              | Main finding                                                                                                                                           |
| ----------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Independent portal databases        | Partial             | One deployment already targets one database, but configuration and operations are hard-wired to one Supabase/Vercel project                            |
| Portal identity and lifecycle       | Implemented         | Private singleton identity, deployment-manifest fencing, sponsor branding and append-only lifecycle events are enforced                                |
| Versioned postcode scope            | Implemented         | Immutable portal scope revisions govern acquisition configuration and reconciliation compatibility                                                     |
| Fleet operations                    | Implemented/partial | A manifest-driven CLI now inventories, migrates, verifies, bootstraps and audits isolated deployments; provider project creation remains adapter-bound |
| Provider abstraction                | Provider-bound      | Request auth, data API, storage, cron and generated types directly use Supabase; deployment directly uses Vercel cron                                  |
| Portal Administrator                | Partial             | Explicit current appointments and revocation evidence replace the implicit capability union; invitation/administration UX remains                      |
| Data Steward / operator             | Partial             | Explicit Data Steward appointments retain revocation evidence and no longer derive from Portal Administrator authority                                 |
| Organisation roles                  | Partial             | Strong grant/revoke safeguards exist; assignments use account UUIDs and no invitation/handoff workflow exists                                          |
| Stewardship                         | Implemented         | Current state/events gate administrator editing; email-bound acceptance atomically grants ownership and completes the handoff                          |
| Record edit audit                   | Partial             | Domain rows retain editor/timestamps and roles/imports have events, but no uniform before/after audit for Portal Administrator edits                   |
| Source releases and private staging | Implemented/partial | Strong per-source releases and runs exist; cross-source campaign aggregation is absent                                                                 |
| Initial seed workflow               | Partial             | ABN candidates and a mandatory independent initial-release gate exist; multi-source seed campaigns remain absent                                       |
| Two-person approval                 | Implemented         | Frozen releases retain policy revisions and require a different approver for initial and destructive work                                              |
| Recurring updates                   | Partial             | ACNC scheduling, reconciliation and conflict protections exist; broader source and campaign orchestration is incomplete                                |
| Review UX                           | Implemented         | Focused validation, identity, field-change, release and suppression queues retain campaign and record context                                          |
| Invitation evidence                 | Implemented         | Immutable email-bound terms and single-use events cover acceptance, cancellation and expiry independently of delivery provider                         |
| NSW state register                  | Missing             | No current adapter is integrated                                                                                                                       |

## Reusable foundations

The following should be preserved and extended:

1. `ingestion.sources`, immutable runs, source records, versions and field
   assertions provide the private evidence boundary.
2. Registry seed releases provide complete-part manifests, private candidates,
   bounded triage and promotion without publication.
3. Structured validation issues, revision-fenced resolutions and derived runs keep
   original evidence immutable.
4. Deterministic identifier claims and identity events prevent unsafe name-only
   merging.
5. Field previews, field state and revision checks protect manual edits.
6. Change sets, publication records, suppression and guarded rollback provide most
   of the transaction primitives needed by a release model.
7. Organisation assignments enforce hierarchy, MFA, last-owner protection and
   browser write denial.
8. Acquisition jobs already use leases, checkpoints, restricted worker authority
   and source/configuration revisions.

These foundations are documented in
[the ingestion strategy](data-ingestion-strategy.md),
[the capability matrix](capability-matrix.md),
[organisation role management](organisation-role-management.md) and
[the ABN seed guide](abn-bulk-seed.md).

## Detailed gaps

### PEG01 — Portal identity, sponsor and lifecycle

**Priority: critical. Status: implemented.**

The private `portal.configuration` singleton establishes which portal a database
represents, its sponsor, display configuration and current lifecycle state.
`portal.lifecycle_events` is append-only, and guarded transition RPCs enforce the
approved lifecycle sequence, administrator authority and scope evidence before the
scope-configured milestone. The application request boundary and cron health check
both fail closed unless `PORTAL_ID` and `PORTAL_KEY` match the database identity.
The root layout renders the active portal and sponsor configuration.

Do not add a portal foreign key to all existing domain tables. Database isolation
already supplies that boundary.

**Acceptance met:** a fresh database cannot serve application requests without an
identity and cannot transition to operational without passing the scope-configured
milestone; lifecycle transitions are authorised and append-only; the UI shows the
active portal rather than a hard-coded global identity. Scope evidence is now an
authoritative PEG02 revision rather than the interim text reference.

### PEG02 — Authoritative postcode scope and re-baselining

**Priority: critical. Status: implemented.**

Immutable portal scope revisions and canonical postcode memberships are private,
append-only governance records. The current 23-postcode boundary is backfilled as
revision 1 for an established deployment. Administrators create later revisions
with policy, impact, reason and re-baseline evidence through a bounded admin page.

ACNC configuration is pinned to the current scope revision and classified as exact,
subset or superset; non-exact configurations require a retained justification.
Jobs and envelopes carry the revision, a scope change cancels obsolete work, and
enqueue rejects stale configurations. Existing completed acquisition jobs receive
an append-only FK-backed attribution without rewriting retained evidence.
Reconciliation rejects runs from different portal scope revisions before
considering source-level scope compatibility.

**Acceptance met:** scheduled acquisition cannot silently diverge from the approved
scope; old runs retain their revision; expansion only records governance state and
does not acquire or publish data; immutable-history and incompatibility regressions
cover the boundary.

### PEG03 — Fleet operations and technical access

**Priority: critical. Status: implemented/partial.**

The separate fleet CLI now validates secret-free manifests, maintains a SQLite
inventory, applies pinned migration targets, verifies portal identity and schema,
bootstraps the first Portal Administrator and exports hash-chained append-only
operation evidence. Credential rotations retain versioned secret references but
never values. Each portal can target an adjacent schema version for rolling upgrades.

The first adapter targets Supabase-compatible PostgreSQL. Provider project creation,
backup/restore execution and time-bounded infrastructure access remain provider
operations and must be recorded with the CLI. They belong to the Phase 6 adapter
contract rather than portal application authority. See [fleet operations](fleet-operations.md).

**Acceptance:** an operator can provision a second test portal, apply and verify the
same schema, appoint its first Portal Administrator, rotate bootstrap credentials
and produce an operation log without changing the first portal.

### PEG04 — Provider boundary

**Priority: high before a non-Supabase deployment. Status: provider-bound.**

The application constructs Supabase clients directly in `hooks.server.ts` and the
root client layout, types `App.Locals` as a Supabase client, uses Supabase Auth and
MFA claims, calls PostgREST RPCs throughout routes, uses Supabase Storage for
avatars, and creates a service-role client in the Vercel cron handler. Static
environment variables assume one project. Database authorization uses
`auth.uid()` and Supabase JWT helpers.

Introduce application-owned interfaces incrementally:

- verified identity and assurance;
- portal database/domain services;
- object storage;
- scheduler/queue trigger;
- secret references; and
- deployment/migration provider.

The initial implementations may delegate completely to Supabase. PostgreSQL
functions and RLS remain a valid data adapter; a different auth provider needs a
trusted way to establish equivalent database identity and assurance.

**Acceptance:** domain loaders/actions no longer require a Supabase type merely to
express business operations, and a provider capability matrix states what an
adapter must implement. A second managed-PostgreSQL proof of concept should follow
before claiming provider portability.

### PEG05 — Portal Administrator conflicts with platform administrator

**Priority: critical. Status: implemented.**

Explicit `portal.capability_appointments` now separates `portal_administrator`
from `data_steward`, and immutable issue/revoke events determine current authority.
The legacy `is_platform_admin()` and `is_ingestion_operator()` functions remain as
compatibility wrappers, but no longer form an implicit capability union. Controlled
legacy-table operations are mirrored into the new evidence model during migration.

This resolves the previous behaviour in which `platform_access.administrators`
granted effective owner and ingestion authority together. Remaining work is the
invitation-based application workflow and administration UI, including a distinct
time-bounded technical-support capability that remains separate from infrastructure
operation.

**Acceptance:** a Portal Administrator can govern the portal and edit an unclaimed
organisation, cannot automatically edit a self-managed organisation, and does not
obtain infrastructure credentials. A support operator has no application access
without a current appointment.

### PEG06 — Organisation stewardship and handoff

**Priority: critical. Status: partial.**

Organisations now have a protected current stewardship projection and append-only
state events. Existing effective owners were baselined as `self_managed`; records
without an owner were baselined as `unclaimed`. Imported creation remains unclaimed.
The database authorization path grants automatic Portal Administrator editing only
for `unclaimed` and `invitation_pending`, and requires approval-backed current
evidence for `portal_managed` and `co_managed`. A transition to `self_managed`
removes that automatic access immediately without a session refresh.

The domain invitation workflow now moves an unclaimed organisation to
`invitation_pending`. Acceptance by the named verified email atomically grants a
non-expiring owner assignment and records either `self_managed` or an explicitly
approved `co_managed` decision. Cancellation and expiry return the organisation to
`unclaimed` and grant no role.

**Acceptance:** handoff immediately removes automatic Portal Administrator edit
authority from existing sessions; imported publication still creates no owner;
portal-managed status cannot arise merely from an expired invitation.

### PEG07 — Invitation and approval-evidence workflow

**Priority: high. Status: implemented.**

Domain invitations are retained independently of the email-delivery provider. Their
immutable terms contain a normalised email, stewardship outcome, expiry, private
approval reference and note. Append-only events permit one terminal acceptance,
cancellation or expiry outcome. The management screen produces a delivery-neutral
acceptance link; the recipient screen requires a registered account whose Auth email
is confirmed and exactly matches the invitation.

Acceptance incorporates the owner-assignment safeguards into the same database
transaction as the stewardship event. Direct table access remains denied, replay
does not duplicate either the assignment audit or the governance history, and an
expired invitation is materialised as a no-grant event when reviewed or opened.
Evidence-document storage remains deferred until its access and retention model is
designed.

**Acceptance:** an invitation cannot be accepted by a different verified email,
cannot be replayed, and atomically creates the intended assignment and stewardship
event. Cancellation and expiry grant nothing.

### PEG08 — Complete record-edit audit

**Priority: high. Status: partial.**

Many domain rows record `last_edited_by` and `last_edited_at`; role, identity,
validation and ingestion decisions have specialised event tables. This does not
produce a uniform before/after record of every Portal Administrator change made
under automatic or continuing stewardship.

Add an application audit event contract for privileged domain writes. It should
record actor, authority path, organisation, action, changed fields or safe diff,
reason where required, request/correlation ID and timestamp. Sensitive values need
redaction rules rather than wholesale logging.

**Acceptance:** every automatic unclaimed-record edit can be reconstructed as who,
what, when and under which stewardship authority; changing attribution fields in a
request cannot forge the actor.

### PEG09 — Campaign and cross-source seed aggregation

**Priority: high. Status: implemented foundation.**

The ingestion model has source-specific runs and registry releases. It does not have
a campaign that pins an ABN release, ACNC run, state-register release, portal scope,
inclusion policy and mapping versions as one establishment or refresh operation.

Campaign records now pin the portal scope revision, its inclusion policy, named
mapping versions, approval policy revision and existing ingestion runs or registry
releases. Readiness is derived over the authoritative source, validation, identity,
field-decision and publication-release records; no raw evidence is copied.

Source-artifact replacements are append-only facts. Recording one makes every
campaign pinned to the old artifact stale while leaving its campaign row and pins
unchanged. Publication releases have an append-only campaign link and are checked
for campaign-type compatibility. Cross-source identity presentation remains part of
the focused queue split rather than a new identity authority.

**Acceptance:** the initial release can state exactly which source observations and
policy versions it used; replacing one source release invalidates downstream
campaign readiness without mutating the previous campaign.

### PEG10 — Publication release and separation of duties

**Priority: critical. Status: implemented.**

Publication releases now freeze exact change-set or suppression actions with a
content hash, policy revision, submitter and immutable release revision. Initial
seed, suppression and destructive releases always require a decision by a different
actor. The Portal Administrator controls whether ordinary updates also require an
independent approver.

Decisions and release events are append-only. Revising contents creates a new
revision without inheriting earlier approval. Publication rechecks the content hash,
frozen change-set snapshot, current source, review, target and suppression state in
the existing transactional writer, then records the exact writes and publisher.

Direct browser publication and suppression RPCs now fail closed. Import Review
submits releases, and the separate release queue handles decisions and execution.
The retained PostgreSQL-superuser compatibility branch exists only for historical
transactional regression tests; provider API sessions cannot use it. Emergency
withdrawal remains deferred until its retrospective-review operating procedure is
defined.

**Acceptance met:** the submitter cannot approve a dual-control release, changing
its contents invalidates approval, and publication atomically records the exact
approved writes, submitter, independent approver and publisher.

### PEG11 — Review information architecture

**Priority: high. Status: implemented.**

The `/admin/ingestion` route is now a task index. Validation, identity and
eligibility, field changes, release decisions, and suppression/withdrawal each have
a focused route with an independently authorised loader and action boundary.

The campaign dashboard reports progress counts, role-labelled blockers, pinned
contracts and publication state, with campaign- and run-aware deep links to:

1. validation issues;
2. identity and eligibility;
3. field changes and conflicts;
4. release submission/approval; and
5. suppression/withdrawal.

Stewardship and invitation administration are likewise separate Portal
Administrator queues. The former records revision-fenced governance decisions; the
latter provides a portal-wide invitation history and cancellation queue while
retaining issuance and atomic handoff in the organisation access workflow.

**Acceptance met:** every screen has one primary decision type, preserves campaign
and record context in navigation, and communicates the next blocker and responsible
role.

### PEG12 — Source and recurring-update completeness

**Priority: high for initial production seeding. Status: partial.**

ACNC acquisition and scheduled reconciliation are implemented. The national ABN
bulk release is privately staged but not triaged or published. Exact-ABN live
qualification is externally gated. No current NSW incorporated-associations adapter
is integrated. Other states will require separate qualified adapters.

Continue P34b–P36, but attach new work to the campaign and portal-scope contracts.
Do not encode NSW or the current Snowy Valleys postcodes into the generic portal
model. Each state provider retains its jurisdiction-scoped identity and access
qualification.

**Acceptance:** a bounded initial campaign combines qualified releases without
name-only merging; recurring comparison is enabled only after a complete comparable
second release; state-specific absence or failure cannot erase organisations.

### PEG13 — Fleet-safe migrations and compatibility

**Priority: high before operating multiple portals. Status: missing.**

The repository has ordered migrations and extensive disposable-database tests, but
deployment records describe one linked hosted project and working-tree deployments.
There is no fleet migration inventory, compatibility window, rolling-upgrade policy
or automated preflight/rollback decision per portal.

Define schema compatibility metadata and provider-neutral migration execution.
Application releases should declare supported schema versions. Prefer expand/migrate/
contract changes so portals can be upgraded independently. Destructive schema
changes require fleet inventory and backup evidence.

**Acceptance:** two portal databases can intentionally run adjacent supported
schema versions; the operator can report drift and failed migration state without
opening each provider console.

### PEG14 — Test topology and policy scenarios

**Priority: high. Status: partial.**

Current suites thoroughly test many authorization and ingestion invariants in one
database. They do not exercise two isolated portals, manifest mismatch, provider
adapters, stewardship handoff, invitations, dual approval or fleet operations.

Add contract tests for every provider adapter and end-to-end scenarios covering:

- two portals with different postcode scopes and users;
- no cross-portal credentials or data access;
- unclaimed edit followed by immediate handoff revocation;
- portal-managed and co-managed authority;
- invitation expiry, cancellation, replay and email mismatch;
- initial/destructive self-approval denial;
- ordinary configurable approval;
- scope revision and reconciliation incompatibility;
- technical support appointment expiry; and
- independent schema upgrade and recovery.

## Recommended refactor sequence

### Phase 0 — Ratify contracts

This design and gap analysis complete the initial architecture decision. Next,
write concise schemas and acceptance tests for portal identity, scope, capabilities,
stewardship, invitations, campaigns and publication releases. Update older role and
capability documentation to distinguish historical behaviour from the target.

### Phase 1 — Portal foundation without behaviour change (complete)

Add the singleton portal identity, lifecycle, scope revisions and deployment
manifest verification. Backfill the current deployment as the first portal and map
its existing 23-postcode configuration to scope revision 1. Keep existing access
wrappers while adding new capability vocabulary.

This phase should not alter published organisation data or ingestion decisions.

### Phase 2 — Governance and stewardship (complete)

Add portal appointments with retained revocation events, stewardship state/events
and the invitation workflow. Route organisation editing through the new authority
decision. Migrate the current platform administrator to an explicitly authorised
bootstrap Portal Administrator only after verifying equivalent required access.

### Phase 3 — Release approvals (complete)

Add publication releases, approval policies and actor separation. Wrap existing
change sets and suppression actions rather than replacing their transactional
checks. Make initial-seed and destructive dual control mandatory.

### Phase 4 — Campaign orchestration and UX split (complete)

Add campaigns referencing existing source artifacts. Build a progress dashboard,
then split validation, identity, change and release queues out of the current Import
Review page. Add stewardship and invitation administration.

### Phase 5 — Fleet operations (complete)

Build the manifest-driven operator capability and a second isolated test portal.
Automate provisioning, migration inventory, health, credential rotation, first
administrator bootstrap and audit export. Retain provider-console access only as a
recorded recovery path.

### Phase 6 — Provider portability proof

Extract Supabase-owned interfaces, document the adapter contract and exercise a
second managed-PostgreSQL provider or an intentionally limited local adapter.
Portability is not complete until authentication identity, storage, scheduling,
backups and migrations meet the same acceptance tests.

### Phase 7 — Complete and operate the seed

Integrate the state-register adapter, cross-source resolution and bounded first
cohort into an `initial_seed` campaign. Publish only through the new dual-controlled
release, complete Portal Administrator handoff, then begin organisation invitations
and recurring refresh campaigns.

## Immediate next slice

Phases 1 through 5 are complete. The fleet control plane now inventories isolated
deployments from secret-free manifests, applies and verifies pinned schema versions,
checks immutable portal identity, bootstraps the first Portal Administrator, records
credential-reference rotations and exports tamper-evident operation history.

The next slice is Phase 6 provider portability: extract application-owned provider
interfaces and prove the required identity, storage, scheduling, backup and migration
capabilities against a second provider or an intentionally limited local adapter.
