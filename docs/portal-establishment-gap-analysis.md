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
has no persisted portal identity or scope history, portal lifecycle, stewardship
state, invitation workflow, release-level separation of duties, multi-source
campaign, provider adapter or fleet operations capability.

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

| Area                                | Status              | Main finding                                                                                                                         |
| ----------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Independent portal databases        | Partial             | One deployment already targets one database, but configuration and operations are hard-wired to one Supabase/Vercel project          |
| Portal identity and lifecycle       | Missing             | No portal singleton, manifest, sponsor or lifecycle events                                                                           |
| Versioned postcode scope            | Partial             | Postcodes exist in ACNC acquisition configuration and seed manifests, not as the authoritative portal scope                          |
| Fleet operations                    | Missing             | Provisioning, migrations, access, recovery and inventory are manual operational procedures                                           |
| Provider abstraction                | Provider-bound      | Request auth, data API, storage, cron and generated types directly use Supabase; deployment directly uses Vercel cron                |
| Portal Administrator                | Conflicting         | `platform_access.administrators` is a database-global appointment with effective owner and ingestion authority                       |
| Data Steward / operator             | Partial             | Operator capability exists but is global within the database and has no application appointment workflow or revocation history       |
| Organisation roles                  | Partial             | Strong grant/revoke safeguards exist; assignments use account UUIDs and no invitation/handoff workflow exists                        |
| Stewardship                         | Missing             | No unclaimed, self-managed, portal-managed or co-managed state                                                                       |
| Record edit audit                   | Partial             | Domain rows retain editor/timestamps and roles/imports have events, but no uniform before/after audit for Portal Administrator edits |
| Source releases and private staging | Implemented/partial | Strong per-source releases and runs exist; cross-source campaign aggregation is absent                                               |
| Initial seed workflow               | Partial             | ABN seed candidate store exists; no complete multi-source seed campaign or initial release gate                                      |
| Two-person approval                 | Missing             | A single operator can approve and publish; no submitter/approver separation exists                                                   |
| Recurring updates                   | Partial             | ACNC scheduling, reconciliation and conflict protections exist; broader source and campaign orchestration is incomplete              |
| Review UX                           | Conflicting         | Validation, record matching, field approval, publication and withdrawal share one large page                                         |
| Invitation evidence                 | Missing             | No email invitation, acceptance, approval reference or invitation events                                                             |
| NSW state register                  | Missing             | No current adapter is integrated                                                                                                     |

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

**Priority: critical. Status: missing.**

There is no singleton record establishing which portal a database represents. The
application name and external links are compiled into the shared layout. There is
no owning/auspicing organisation, lifecycle state or transition history.

Add a portal configuration schema with exactly one portal identity, sponsor details,
display/branding configuration and immutable lifecycle events. Enforce singleton
semantics in the database. Application startup and health reporting should fail
closed if the manifest and database identity disagree.

Do not add a portal foreign key to all existing domain tables. Database isolation
already supplies that boundary.

**Acceptance:** a fresh database cannot become operational until its identity and
scope are configured; lifecycle transitions are authorised and append-only; the UI
shows the active portal rather than a hard-coded global identity.

### PEG02 — Authoritative postcode scope and re-baselining

**Priority: critical. Status: partial.**

ACNC acquisition configuration accepts one to fifty postcodes, and the ABN seed
manifest retains selection scope. These are source-specific settings. There is no
authoritative versioned portal scope against which source configurations are
validated.

Add portal scope revisions and postcode memberships. Source acquisition
configuration must reference a scope revision or explicitly document a justified
subset/superset. A scope change creates an impact assessment and, normally, a
`scope_rebaseline` campaign. Reconciliation must reject incomparable revisions.

**Acceptance:** no scheduled acquisition silently uses a postcode set different
from the approved portal scope; old runs remain attributable to the old revision;
scope expansion cannot create or publish organisations by itself.

### PEG03 — Fleet operations and technical access

**Priority: critical. Status: missing.**

Current provisioning, hosted migration, source enablement, worker deployment and
production verification are recorded as manual project operations. There is no
fleet inventory, provider adapter, just-in-time access, credential rotation workflow
or cross-deployment schema reporting.

Build a separate control plane or operator CLI/service before the portal count makes
manual operation unsafe. Its first version can be manifest- and CLI-driven, but it
must maintain an inventory and append-only operation records. Portal databases must
not store fleet-wide secrets.

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

**Priority: critical. Status: conflicting.**

`platform_access.administrators` grants effective owner access across every
organisation and is folded into `is_ingestion_operator()`. Within a single database
this currently supplies the escape hatch, but it cannot distinguish:

- portal governance;
- editing an unclaimed organisation;
- continuing portal-managed stewardship;
- technical support; or
- infrastructure operation.

Replace this implicit union with explicit portal capabilities. Because a database
contains one portal, appointments need not carry `portal_id` locally, but must carry
capability, issuer, reason, validity and revocation events. Retain a bootstrap path
for the first appointment.

The existing `is_platform_admin()` name and its effective-owner behaviour should be
deprecated through compatibility wrappers, not changed silently beneath deployed
policies.

**Acceptance:** a Portal Administrator can govern the portal and edit an unclaimed
organisation, cannot automatically edit a self-managed organisation, and does not
obtain infrastructure credentials. A support operator has no application access
without a current appointment.

### PEG06 — Organisation stewardship and handoff

**Priority: critical. Status: missing.**

Organisations have public visibility and role assignments but no governance state.
Imported creation deliberately avoids granting an owner, which is the correct base
behaviour, but the application cannot distinguish an unclaimed record from one the
portal has agreed to manage.

Add current stewardship state plus append-only stewardship events. Update edit and
role-management authorization so automatic Portal Administrator editing is derived
from `unclaimed` or `invitation_pending`, while `portal_managed` and `co_managed`
require explicit effective authority. Invitation acceptance must change state and
grant ownership in one transaction.

**Acceptance:** handoff immediately removes automatic Portal Administrator edit
authority from existing sessions; imported publication still creates no owner;
portal-managed status cannot arise merely from an expired invitation.

### PEG07 — Invitation and approval-evidence workflow

**Priority: high. Status: missing.**

The current access screen grants an existing role using a registered account UUID.
Supabase can process a generic Auth invitation callback, but there is no domain
invitation, email match, approval reference, expiry, acceptance or event history.

Implement domain invitations independently of the email-delivery provider. Retain
the hardened assignment RPCs as the final grant primitive or incorporate their
safeguards into transactional acceptance. Add a private approval reference and note;
defer evidence-document storage until its access and retention model is designed.

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

**Priority: high. Status: partial.**

The ingestion model has source-specific runs and registry releases. It does not have
a campaign that pins an ABN release, ACNC run, state-register release, portal scope,
inclusion policy and mapping versions as one establishment or refresh operation.

Add campaign metadata and stage readiness without copying raw evidence. Existing
runs/releases should be referenced. A campaign-level identity queue groups source
identities while preserving their independent assertions. Existing deterministic
identity primitives should remain authoritative.

**Acceptance:** the initial release can state exactly which source observations and
policy versions it used; replacing one source release invalidates downstream
campaign readiness without mutating the previous campaign.

### PEG10 — Publication release and separation of duties

**Priority: critical. Status: missing over partial primitives.**

Current change sets and publication functions protect revisions and manual edits,
but the capability matrix explicitly permits one operator to approve and publish.
There is no release submitter, independent approver, approval policy, frozen release
revision or destructive-action classification.

Wrap bounded change sets in publication releases. Submission freezes a revision;
approval is a separate append-only decision; publication rechecks the frozen
revision and actor separation. Initial and destructive releases require a distinct
approver. Ordinary policy is stored in portal configuration.

Suppression currently acts through the review workspace and must be incorporated
into the destructive release policy. Emergency withdrawal remains a narrow,
audited exception followed by retrospective review.

**Acceptance:** the submitter cannot approve a dual-control release, changing its
contents invalidates approval, and publication atomically records the exact
approved writes and both actors.

### PEG11 — Review information architecture

**Priority: high. Status: conflicting UX.**

The current `/admin/ingestion` route loads validation queues, run records, matching
candidates, field previews, saved approvals and withdrawal state. The page presents
validation, identity review, field approval, publication and suppression in one
long workspace. Acquisition and source configuration are separate pages, but the
overall flow is run-centric rather than campaign- or task-centric.

Introduce the target navigation incrementally. Start with a campaign dashboard and
deep links to the existing screens, then split one decision queue at a time:

1. validation issues;
2. identity and eligibility;
3. field changes and conflicts;
4. release submission/approval; and
5. suppression/withdrawal.

Do not redesign the visual layer before the campaign and stewardship states exist;
otherwise the same conceptual coupling will reappear across prettier screens.

**Acceptance:** every screen has one primary decision type, preserves campaign and
record context in navigation, and communicates the next blocker and responsible
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

### Phase 1 — Portal foundation without behaviour change

Add the singleton portal identity, lifecycle, scope revisions and deployment
manifest verification. Backfill the current deployment as the first portal and map
its existing 23-postcode configuration to scope revision 1. Keep existing access
wrappers while adding new capability vocabulary.

This phase should not alter published organisation data or ingestion decisions.

### Phase 2 — Governance and stewardship

Add portal appointments with retained revocation events, stewardship state/events
and the invitation workflow. Route organisation editing through the new authority
decision. Migrate the current platform administrator to an explicitly authorised
bootstrap Portal Administrator only after verifying equivalent required access.

### Phase 3 — Release approvals

Add publication releases, approval policies and actor separation. Wrap existing
change sets and suppression actions rather than replacing their transactional
checks. Make initial-seed and destructive dual control mandatory.

### Phase 4 — Campaign orchestration and UX split

Add campaigns referencing existing source artifacts. Build a progress dashboard,
then split validation, identity, change and release queues out of the current Import
Review page. Add stewardship and invitation administration.

### Phase 5 — Fleet operations

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

The lowest-risk implementation slice is Phase 1:

1. Define `portal_identity`, `portal_lifecycle_events`, `portal_scope_revisions`
   and `portal_scope_postcodes`.
2. Add a read-only portal context service used by the root layout and admin hub.
3. Validate ACNC acquisition postcodes against the current portal scope while
   retaining an explicit exception mechanism.
4. Add manifest/schema/scope information to the health check.
5. Backfill the current deployment without changing authorization or publication.
6. Add disposable-database tests for singleton identity, immutable scope history,
   lifecycle transitions and incompatible reconciliation scope.

This establishes the boundary required by every later phase while leaving the
deployed ingestion and organisation workflows intact.
