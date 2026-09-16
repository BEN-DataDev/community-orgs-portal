# Portal implementation plan

Prepared: 15 September 2026. Updated: 16 September 2026 after acquisition-code review.
Status: pilot source approval and publication workflow browser-verified by the user. Full register field coverage is the next priority; acquisition job controls and scheduling are deferred.

## Current priority: complete import fields

Implement [the complete public register field coverage plan](import-field-coverage-plan.md)
(F01–F05) before acquisition job controls or scheduling. It uses the reviewed
transformation, mapping and parsing modules from both referenced repositories.
F01 is complete: see [the generated ACNC field inventory](acnc-field-coverage.md).
F02 schema/transformations, F03 review/publication and F04 public pages are
implemented and locally tested. Next implement F05 retained-pilot replay.

## Recommendation

Start with a small, complete workflow: an operator imports source records, reviews
matches and changes, publishes a batch, and an authorised organisation editor can
correct the resulting page without the next import overwriting their work.

This makes the order of work:

1. Resolve the pilot scope and access boundaries; fix the known broken search.
2. Define the import/review/edit workflows with simple screen sketches.
3. Add the minimum role and database foundations those workflows need.
4. Ingest a small source sample into private staging and produce a change preview.
5. Build review/publication UI and finish the editing gaps that imported records expose.
6. Publish a reviewed pilot, then add refresh and maintenance automation.
7. Expand sources, domain screens and visual polish from pilot feedback.

UX starts early as workflow design. Detailed UI design follows real sample data.
Source samples should inform migrations before they are finalised. Broad data
collection waits until matching, provenance and publication controls exist.

## Basis and limits

This plan combines the [gap analysis](gap-analysis.md) and
[ingestion strategy](data-ingestion-strategy.md). The former documents the current
repository; the latter records researched source options and proposed ingestion
architecture. Old examples in the other domain documents remain reference material.

There is enough information to plan and start the first engineering tasks. Exact
source schemas, hosted database state, provider permissions and operational ownership
must be verified at the relevant milestones. This plan does not assume those checks
have already happened.

### Working defaults

- Pilot: Snowy Valleys and nearby communities, with a configurable boundary.
- Initial target: approximately 50–100 reviewed records, including existing records,
  duplicate candidates and groups without ABNs. This is a proposed test cohort.
- Initial sources: ACNC Register and approved CSV files; ABN verification when access
  is available. No AIS financial-history import in the first release.
- Access: retain current organisation roles; add a distinct platform ingestion role.
- Publication: operators approve new records and changes during the pilot.
- UI: extend the current Svelte/Skeleton interface and navigation conventions.
- Scope: keep branches and services distinct; defer ambiguous cases until their
  mapping is resolved rather than merging on a shared name or ABN.

These defaults allow work to proceed without choosing every later feature now.

## Progress: offline ACNC first step

On 16 September 2026, implemented the isolated ACNC prototype under
`tools/ingestion/python`. It records upstream provenance, fixes address-line loss,
passes 15 fixture tests and generates a reproducible JSON envelope. No network or
database operations are enabled. See the [schema review](acnc-prototype-schema-review.md)
for mapping decisions and precise R01–R04 coverage. ABN/NSW qualification and SvelteKit integration remain outstanding; the multi-provider tasks are
not marked complete by this ACNC-only prototype.

### Progress: source qualification and staging

Validated six live ACNC records for postcode 2730, with the current resource and
licence metadata recorded. Implemented the private staging migration and SQL-export
command. Seventeen Python tests and disposable PostgreSQL regression tests pass;
replaying the live sample left one run and six versions. See
[private staging](private-staging.md). P04/P09 now have an ACNC foundation; source
administration, private object retention, worker identity deployment and the other
providers remain pending. No hosted migrations or public records were changed.

## Acquisition foundation: reuse existing Python code

Follow the [acquisition assessment](acquisition-code-assessment.md): adapt the
ACNC, ABN and NSW extractor classes from `orgs-sveltekit-etl`; use
`orgs-data-manager` locality configuration, parser checks and mappings as supporting
references. Both are Python codebases. Preserve the portal's TypeScript UI and
server authorization while running extraction in an isolated Python worker.

Before source integration, add these tasks to Milestone 0:

| ID  | Task                                                    | Acceptance                                                                                                              |
| --- | ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| R01 | Pin upstream modules and record reuse rights/provenance | Manifest contains reviewed commit, source/local paths and changes                                                       |
| R02 | Isolate clients and package dependencies                | CSV/ACNC tests run without Flask, Redis, ABN credentials or database startup; reproducible minimal environment          |
| R03 | Characterise and correct parsers/mappings               | Fixtures cover ACNC address loss, ABN key mismatches, namespace shapes, NSW pagination and failure versus empty results |
| R04 | Define Python-to-staging contract                       | Versioned records retain source IDs, raw evidence, typed assertions, scope and complete/partial/failed states           |

R01–R04 inform P04/P09 and must complete before P13/P16 live integration. Their
fixture work can proceed alongside scope, roles and schema design. The supplied
loaders and automatic name-based merge are replaced, not connected to portal tables.
A public Flask service and Redis are not required for the pilot.

## Release objective

The pilot is complete when an authorised operator can import, review and publish
the test cohort, a permitted editor can correct it, and a second import demonstrates
safe matching and preservation of manual edits. Users can browse the resulting
records with clear source attribution and freshness information.

## Sequenced backlog

### Milestone 0 — Scope, sample data and baseline

**Indicative effort: 2–3 engineering days.**

| ID  | Task                                       | Deliverable / acceptance                                                                                                                        |
| --- | ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| P01 | Write the pilot inclusion policy           | Area, categories, entity/group/service distinctions and exclusions are explicit                                                                 |
| P02 | Fix relationship UUID conversion (gap G01) | Partner search uses string IDs, excludes the current organisation and surfaces failures; browser creation succeeds                              |
| P03 | Capture a development baseline             | Record check/build results and relevant SQL test results against a disposable/local database; identify hosted migration drift before deployment |
| P04 | Qualify source samples                     | Record exact resource/version, licence, attribution and schema for a small ACNC sample and CSV fixture; start ABN access preparation            |
| P05 | Sketch the core journeys                   | Import → match → field review → publish; organisation edit → conflict review; reject/withdraw → suppress                                        |

**Exit:** a representative sample, agreed working scope and reviewable workflow
sketches exist. Current application failures are distinguished from proposed work.

P04 can proceed alongside the search fix and UX sketches. Waiting for provider
access must not prevent fixture-based development, but fixtures do not substitute
for access approval or real-format validation.

### Milestone 1 — Access boundaries and schema

**Indicative effort: 1–2 weeks. Depends on P01, P04 and P05.**

| ID  | Task                                           | Deliverable / acceptance                                                                                                                                       |
| --- | ---------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P06 | Define the capability matrix                   | Separate public reader, organisation member/admin/owner, ingestion operator and platform administrator                                                         |
| P07 | Implement scoped operator access               | Global ingestion controls cannot be used merely because someone administers one organisation; reads and mutations enforce this server-side and in the database |
| P08 | Implement minimum organisation role management | List assignments, grant/revoke existing roles using authorised RPCs; enforce actor/target scope and MFA requirements                                           |
| P09 | Add private ingestion storage                  | Sources, runs, source records/versions, links, assertions and change sets; raw objects are private and retained under source policy                            |
| P10 | Add publication and edit protection            | Explicit publication state/visibility, revision checks, manual field ownership, publication events and suppression rules                                       |
| P11 | Define identifier and entity mapping           | Jurisdiction-scoped identifiers, legal-entity versus branch/service rules, duplicate constraints and a migration path for existing records                     |

Before finalising migrations, compare proposed fields with actual source headers and
existing portal records. Preserve the existing `org_id` UUIDs and relationships.
Do not introduce a global unique ABN constraint across legal entities and branches
without first resolving the entity model.

Imported records must not accidentally become publicly visible through the current
`is_public` default or grant the importing operator ownership via an insert trigger.
Test both behaviours explicitly. Platform-role bootstrapping should be an audited
deployment operation, not a role that users can grant themselves.

**Exit:** schema migrations and rollback/forward-repair procedures are reviewed;
unauthorised users cannot access staging or global controls; existing organisation
permissions continue to work. No source records have been published automatically.

Full custom role builders, new permission hierarchies and ABAC are deferred.
Role request/review UI can follow the minimum assignment workflow; the existing RPCs
provide a starting point but must be tested against their current authorization rules.

### Milestone 2 — Import and preview one batch

**Indicative effort: 1–2 weeks. Depends on P09–P11.**

| ID  | Task                                   | Deliverable / acceptance                                                                                                      |
| --- | -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| P12 | Build approved CSV importer            | Validates source metadata and rows; malformed entries are quarantined with reasons                                            |
| P13 | Adapt existing Python ACNC extractor   | Qualifies configured CKAN resource/schema; emits versioned staging records and manifest; supports a bulk-resource fallback    |
| P14 | Add deterministic matching             | Existing source link, verified ABN and jurisdiction-scoped incorporation number; conflicting/ambiguous records go to review   |
| P15 | Generate field-level changes           | Preview new, unchanged, changed, conflicting, rejected and missing records, with evidence and prior revisions                 |
| P16 | Adapt existing Python exact-ABN lookup | Injects credentials, fixes parser/transformer contracts and bounds SOAP calls; unavailable access leaves verification pending |
| P17 | Add transactional publication service  | Applies an approved immutable change set, checks revisions and records exact before/after values                              |

The first output is a dry-run report against the test cohort. Inspect it before
enabling publication. An unchanged replay must produce no new entities or public
changes. Do not treat a missing field as false, or annual revenue as annual budget.

**Exit:** a batch can be fetched, staged, matched and previewed reproducibly. The
publication service is tested with fixtures, including stale approvals and retries.
ABN GUID availability gates live verification, not the entire pipeline.

### Milestone 3 — Review UI and editable pilot records

**Indicative effort: 1–2 weeks. Depends on P07, P15 and P17.**

| ID  | Task                                   | Deliverable / acceptance                                                                                      |
| --- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| P18 | Build source/run dashboard             | Operators see access status, freshness, counts and failures                                                   |
| P19 | Build match/change review              | Side-by-side evidence; link/create/defer/reject decisions; approve only selected fields and records           |
| P20 | Expose publication and history         | Batch preview, publish result, attribution and change history; no stale approval can overwrite later edits    |
| P21 | Complete minimum editing workflows     | Edit existing aliases, locations and document links (G05); display saved business-name aliases                |
| P22 | Add relationship correction            | Authorised editing and end dates (G03); keep partner model changes separate unless P11 requires them          |
| P23 | Integrate manual edits with provenance | Existing forms create protected field revisions; later imports show conflicts instead of silently overwriting |
| P24 | Show sources and freshness publicly    | Safe source links/check dates; distinguish register facts from organisation-confirmed details                 |

Use actual sample records to check long names, missing data, duplicates, conflicting
addresses, narrow screens and keyboard navigation. For Skeleton changes, follow
the local documentation workflow in `AGENTS.md` and verify installed APIs.

**Exit:** an operator can maintain the pilot through the UI, and organisation editors
can correct their own records. A public visitor cannot see staged/rejected records.

### Milestone 4 — Controlled publication and maintenance

**Indicative effort: about 1 week. Depends on Milestone 3.**

| ID  | Task                                           | Deliverable / acceptance                                                                                |
| --- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| P25 | Publish the reviewed cohort                    | Review inclusion/matching decisions; publish an attributable batch; inspect representative public pages |
| P26 | Add scheduled jobs                             | Bounded worker, leases, checkpoints, retry/backoff and source pause controls                            |
| P27 | Reconcile complete snapshots                   | Failed/partial runs cannot mark organisations closed or delete data                                     |
| P28 | Implement withdrawal and correction operations | Suppress affected fields, propagate required removals and prevent replay restoring them                 |
| P29 | Implement guarded rollback                     | Reverse import changes when revisions still match; queue conflicts with later human edits               |
| P30 | Run a second import cycle                      | Demonstrate unchanged replay, a legitimate change, a manual conflict, source failure and withdrawal     |

The existing cron route should enqueue bounded work rather than parse national
extracts within an HTTP request. Choose worker hosting after measuring sample
runtime, memory and expected volume.

**Exit:** the end-to-end release objective is met. Record import quality, unresolved
matches, source freshness, reviewer effort and operating cost. Expand only when the
team can handle the resulting review queue.

### Milestone 5 — Expand from measured needs

Schedule these after the pilot, in the order supported by coverage and user feedback:

| Work                                                                | Dependency / reason                                                                                                             |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| NSW associations feed/import                                        | Adapt reviewed NSW Python scraper after access/markup qualification, or use approved export; broadens coverage beyond charities |
| Landcare, neighbourhood houses and selected sports/arts directories | Provider-specific terms; supports informal groups and local services                                                            |
| My Community Directory adapter                                      | Partner agreement and technical documentation                                                                                   |
| Role requests and representative claims                             | Agreed verification policy and tested request/review permissions                                                                |
| Social media, insurance and auditor UI (G07)                        | Actual use cases and suitable structured forms                                                                                  |
| Governance/programs/accreditation/assets/metrics screens (G06)      | Defined domain workflows; prioritise services if directory users need them                                                      |
| Global relationship list/detail routes (G03)                        | Demonstrated need beyond organisation-specific navigation                                                                       |
| AIS financial history (G08)                                         | Period-aware schema and explicit financial-measure definitions                                                                  |
| Geocoding and service-area improvements (G09)                       | Address roles, provider terms and geographic requirements                                                                       |
| Reports (G12)                                                       | Agreed questions and sufficiently complete data                                                                                 |
| Broader visual redesign                                             | Evidence from working user journeys and content                                                                                 |
| ABAC (G11)                                                          | Specific access requirements that current roles cannot reasonably express                                                       |

## First implementation batch

Start with **P01–P05 and R01–R04**. Keep changes reviewable in small units:

1. Relationship UUID/search fix with a focused regression check and browser verification.
2. Pilot policy, capability matrix draft and workflow sketches.
3. Pin and isolate the reused Python clients; add source manifests and contract fixtures with corrected mappings.
4. Demonstrate fixture extraction to the staging envelope; use that sample to inform the migration proposal before application.

The next batch is **P06–P11**, followed by the importer. This keeps immediate bug
fixes moving while avoiding premature schema expansion or a large redesign.

## Testing and release gates

| Gate             | Required evidence                                                                                  |
| ---------------- | -------------------------------------------------------------------------------------------------- |
| Access           | Cross-organisation and non-operator denial tests; RLS checks; no importer ownership grants         |
| Matching         | Labelled fixture set covering duplicates, shared ABNs, branches, common names and no identifiers   |
| Publication      | Transactional revision checks, idempotent replay and explicit visibility                           |
| Editing          | Manual corrections survive refresh; conflicting proposals require review                           |
| Failure recovery | Interrupted jobs resume; incomplete snapshots cannot trigger removal                               |
| Withdrawal       | A suppressed record/field is removed from publication and cannot return on replay                  |
| UX               | Keyboard and responsive checks for review/publish/edit; browser tests against a disposable dataset |
| Regression       | Appropriate existing account/security tests plus Svelte checks/build after implementation changes  |

Use source fixtures for routine tests. Live provider tests should be bounded and
separate from ordinary CI. Test migrations on disposable/local data, then verify
deployment state before applying them to the hosted environment.

## Decisions and when they matter

| Decision                         | Needed by                     | Proposed default                                                       |
| -------------------------------- | ----------------------------- | ---------------------------------------------------------------------- |
| Pilot geography/categories       | P01                           | Snowy Valleys and nearby communities; a small multi-sector cohort      |
| Legal entity/group/service model | P11                           | Separate identities/scopes; never merge merely because ABNs are shared |
| Who approves publication         | P06–P07                       | Explicitly appointed platform operators                                |
| Custom roles or ABAC             | No pilot dependency           | Retain organisation roles and add a narrow platform capability         |
| Source permissions/credentials   | Each live adapter/publication | Disable sources whose access or reuse remains unresolved               |
| Financial history                | Expansion                     | Exclude AIS financial import from pilot                                |
| Hosting and operating budget     | P26                           | Bounded scheduled worker selected after measurements                   |
| Representative claims            | Claim workflow                | Reviewed claim; imported records confer no account ownership           |

## Effort and scope control

For one engineer, allow roughly **6–9 engineering weeks** for the integrated pilot,
with review availability and provider access affecting elapsed time. Re-estimate
after Milestones 0 and 2, including R01–R04. Reuse may shorten adapter work, but
does not remove hardening, staging, review or publication work. This refines the ingestion strategy estimate to include
minimum roles and editing integration; the two estimates are not additive.

The pilot does not depend on closing every item in the gap analysis. It needs
correct identity, controlled publication, traceability and maintainable records.
Broader screens and additional sources should become separate accepted tasks.

Update this plan as tasks complete, recording evidence and any scope changes.
Update the affected domain documents alongside implementation rather than leaving
older examples to contradict the working application.

## Operator review increment — 16 September 2026

Implemented `/admin/ingestion`: run selection, paginated records, source evidence,
ABN/name candidates, manual name search and version-scoped link/create/defer/reject
proposals. Explicit platform operators are appointed in private storage; organisation
admin/owner roles do not grant ingestion access. Saved proposals have optimistic
revision checks and an append-only event trail accessible to database administrators.

This advances **P07, P09, P14, P18 and P19**, without completing those tasks.
Candidates are suggestions; there is no automatic merge or verified identifier
link. Initial field-level comparisons are described below; selected-field approval, publication, suppression,
source administration and a history UI remain outstanding. Source/run browsing
currently lists the latest 50 runs and 50 records per page.

Validation: Svelte check, production build, route regressions and rollback-only
PostgreSQL review tests passed. SQL verification used a disposable PostgreSQL 16
container with minimal auth/portal fixtures; the hosted migration chain and browser
workflow against a deployed Supabase instance remain unverified. See
[operator review setup](private-staging.md#operator-review).

The field-preview increment below advances P10/P15. Deploy and verify the review
workflow on a chosen development Supabase instance before pilot use.

## Field preview increment — 16 September 2026

Added current/source comparisons to import review and database-managed protection
for name, ABN and website. Existing values are protected during migration; edits,
clears and child-row deletions advance revisions. Missing source fields preserve
portal values; unmapped fields and ambiguous child rows remain review-only.

This advances **P10/P15/P19/P23** but does not complete them. Mapping is limited to
three fields. Immutable field selections, stale-approval checks at publication,
conflict resolution, suppression and imported-field provenance remain outstanding.
See [field protection details](private-staging.md#field-previews-and-protection--16-september-2026).

The publication increment below adds selected-field change sets and transaction
checks for target protection and revisions.
The hosted database has not been migrated; full development deployment/browser
verification remains a release gate.

## Publication increment — 16 September 2026

Implemented immutable selected-field approvals and transactional publication for
name, ABN and website. Operators approve a saved link/create target, inspect the
saved values and publish separately. The database validates the review revision,
field snapshot, protection, source availability/completeness and native source link.
New organisations are public; existing visibility is preserved. The existing
owner-grant trigger skips privately marked imports and still grants ownership for
normal portal creation. Publication is atomic and idempotent by approval ID, with private history.

This advances **P10/P15/P17/P19/P20** for the bounded three-field pilot. Imported
values remain protected; automatic refresh/conflict overrides, suppression,
withdrawal, public attribution and guarded rollback remain unfinished. Table-level
publication locks are appropriate only for a small pilot until measured/reworked.
See [publication setup and constraints](private-staging.md#selected-field-approval-and-publication--16-september-2026).

Validation: isolated PostgreSQL regression tests and Svelte route tests cover
failure rollback, stale approvals, manual corrections, replay, duplicate creation,
source pauses and partial runs. Development Supabase deployment, its full migration
chain and browser verification remain release gates before any real publication.

Next: verify the complete workflow on a designated development Supabase instance,
then add public source attribution and withdrawal/suppression before cohort release.

## Platform administrator — 16 September 2026

Applied `20260916015048_platform_administrators.sql` through Supabase MCP to
`gqltsfijginclwszrcfj`. Explicitly granted user
`2b902bc4-832e-40fb-9c64-6948c57f5c65` platform administration at the user's request.
The private `platform_access.administrators` table records the grant and reason.
This grants application-wide organisation access and owner-level role management
without creating per-organisation memberships. Admin navigation now checks this
explicit capability; organisation administrators retain their scoped access.

Existing MFA and anonymous-session restrictions remain. Client roles cannot read
or modify the grant table. A database administrator can revoke access by deleting
the user's row. This does not grant Supabase dashboard access or database superuser
rights. Ingestion integrates the capability when its migrations are deployed;
the earlier ingestion/publication migrations remain undeployed on the remote DB.

Validated local RLS/private reads, denied self-grants/non-admin access and immediate
revocation. Confirmed the real grant through an authenticated database claim
simulation. Application changes are in the workspace and require the usual web
application deployment for hosted navigation to use the new capability.

## Development activation — 16 September 2026

Applied the four ingestion migrations through Supabase MCP to the existing project
`gqltsfijginclwszrcfj` (the same project configured by the local development app):

| Migration                  | Remote version   |
| -------------------------- | ---------------- |
| Private staging            | `20260916020403` |
| Operator review            | `20260916020406` |
| Field preview/protection   | `20260916020408` |
| Selected-field publication | `20260916020409` |

Local migration filenames now match the remote ledger; no migration-history rows
were rewritten. This supersedes earlier notes saying these migrations are undeployed.
No source was enabled and no records were staged or published.

The local Vite app runs at `http://127.0.0.1:5174` (5173 was occupied). Sign-in
returns HTTP 200; unauthenticated admin/ingestion requests redirect to sign-in.
Under authenticated AAL2 claims for user `2b902bc4-832e-40fb-9c64-6948c57f5c65`,
Supabase confirms platform-admin and ingestion-operator access and returns a valid
empty review queue. All ingestion tables have RLS; authenticated users have no
direct private-schema access. Svelte checks and admin/ingestion route tests pass.

An actual signed-in browser session was not available for this verification;
interactive login, navigation and rendered review verification remain pending.
This starts the local app; it does not deploy a hosted web application.
Next: sign in locally, then stage a synthetic sample and exercise review/publication.

## Synthetic workflow verification — 16 September 2026

Staged `offline-acnc-sample-v1` as **run 1**, containing two private synthetic
records, in the configured Supabase project. The enabled source resource is
`synthetic-acnc-resource-v1`; its metadata explicitly identifies it as synthetic.
No live ACNC source was enabled. Python fixture/hash validation: 17 tests passed.

Added `supabase/tests/ingestion_deployed_workflow.sql` and exercised the deployed
schema under authenticated operator claims for the appointed administrator. Passed:
queue/detail loading, create review, stale-review rejection, selected-field approval,
publication, idempotent retry, duplicate creation rejection, manual-edit protection,
no ownership assignment and exclusion of unselected ABN data. This checks the
actual hosted triggers and RLS, superseding the earlier minimal-schema limitation
for this scenario. It is a database integration test, not a browser automation test.

The entire review/publication exercise was rolled back. Only the private source,
run and two staged records remain; there are no saved reviews, approvals, published
organisations or publication events from this test. Open Admin → Import review →
`offline-acnc-sample-v1` to inspect the staged examples. They are synthetic and must
not be presented as real community organisations.

MCP's postgres connection could not assume `ingestion_worker`. Staging therefore
used its existing execute privilege directly; no memberships or grants were changed.
The dedicated worker login/membership still needs provisioning for scheduled jobs.

Next implementation: public source attribution (P24), followed by suppression and
withdrawal controls (P28) before real-cohort publication. Interactive review and
approval in the signed-in browser remains a separate verification step.

## Attribution and suppression increment — 16 September 2026

Applied `20260916034216_attribution_and_suppression.sql` to the configured Supabase
project. Organisation overview pages now show per-field sources, observed/published
dates, licence metadata when supplied and whether the value was edited since import.
Only an explicit public projection is exposed; raw records and private review notes
remain private. Links are restricted to HTTP(S) without embedded credentials.

Admin → Import review now includes withdrawal/suppression controls. Operators can
clear a linked ABN/website or make the entire linked organisation private, with a
required reason and confirmation. Clearing a field checks the displayed snapshot;
changed/ambiguous targets require reloading. Explicit removal also clears human
corrections, which the form states. Suppression is retained across source versions
and enforced during approval, publication and direct target updates. No operator
UI can undo suppression. Whole-record withdrawal applies to the entire linked
organisation, including organisations that existed before the import.

This advances **P24/P28** for the three-field pilot. It does not erase private raw
archives/audit history, purge external caches, implement an unsuppression workflow
or identify duplicates under unrelated native/resource IDs. Required name removal
uses whole-record withdrawal. Source metadata qualification and public licence
text still need operator review before real publication. Public source links use
reviewed `public_*` metadata, not arbitrary links copied from raw records.

Validation: Svelte, targeted lint, build, route tests and safe-link tests passed.
Isolated and deployed-schema rollback tests cover public attribution, manual edits,
stale-removal rejection, replay/direct restoration denial, later source versions,
withdrawal and unauthorised access. Remote tests left zero public organisations,
publications or suppressions; the two earlier private synthetic records remain.
Browser rendering of this new workflow remains unverified.

Next: bounded live ACNC acquisition and source configuration for the pilot (P13/P18),
with current metadata/schema validation and disabled-by-default source enablement.
Keep real publication separate from acquisition until the source terms and mapping
have been reviewed. Full rollback operations and scheduled refresh remain later work.

## Bounded live ACNC acquisition — 16 September 2026

Implemented `ingestion.live_acnc` and disabled-by-default pilot configuration in
`tools/ingestion/python/config/acnc-pilot.json`. The client bounds postcode scope,
page count/size, response bytes, HTTP requests, timeout and retries. It qualifies
resource membership/activity, reviewed licence title and field schema, rejects
out-of-scope rows and rechecks metadata after pagination. It emits private evidence
for complete/partial/failed runs and never publishes or opens a database connection.

The live postcode **2730** pilot completed with **6 accepted records**, **2 pages**,
**0 quarantined records**. Metadata and field schema remained consistent. See
[qualification evidence](acnc-live-pilot-validation.json); raw data stays outside
the repository. Records were staged via Supabase MCP as **run 6**. The source has
reviewed public attribution metadata but is **paused after staging**, preventing
field approval/publication until separately enabled for the pilot. Existing
synthetic records and withdrawn test organisations were not modified.

This advances **P13/P18**. Source configuration is file/database based; the operator
source-management UI, worker identity, scheduled runs, bulk-resource fallback and
stable cross-release native-ID qualification remain outstanding. Scoped CKAN
completion is not a guarantee of a national or atomic snapshot.

Validation: 26 offline Python tests pass, including scope rejection, malformed
schema, metadata drift, retry/byte/time budgets and Retry-After handling. The real
network run used four requests (metadata, two data pages, metadata recheck).

Next: inspect run 6 in Admin → Import review, qualify the pilot inclusion/matching
and public attribution before enabling publication. Build source enable/pause and
job controls before scheduled acquisition.

### Source approval administration (16 September 2026)

- Added **Admin → Source approvals** (`/admin/sources`) and a contextual link
  beside field approval errors caused by paused sources or incomplete imports.
- Platform admins can inspect source licence, staging evidence, recent imports
  and status history, then explicitly enable or pause the source/resource with
  a reason and confirmation. Returning to review preserves the run and record.
- Source changes use authenticated, admin-only RPCs, locked source snapshots and
  private audit events. Enabling does not publish records or permit incomplete
  imports; it enables the whole source/resource for staging and review operations.
- Applied migration `20260916060046_source_approval`. The live ACNC source was left
  paused for explicit admin approval. Acquisition metadata is historical;
  the displayed current status and status-change history are authoritative.
- Verified route authorization/validation/stale responses, existing ingestion
  route tests, Svelte check and targeted ESLint. Database enable/pause/audit/stale
  checks passed in a rolled-back transaction.
- User confirmed the browser workflow works for ABN **75349327058**: source
  enablement, field approval, publication and checking the resulting organisation
  and source attribution. This is user-reported verification.
- Next (revised after field-coverage review): complete F01–F05 in the
  [import field coverage plan](import-field-coverage-plan.md). Acquisition job
  controls, refresh scheduling and changed-record detection follow this work.

### F01 complete — ACNC field inventory and mapping contract

- Accounted for all 70 columns in the observed ACNC schema: 69 public organisation
  facts and one private technical row ID. See [coverage table](acnc-field-coverage.md)
  and [machine-readable manifest](../tools/ingestion/python/ingestion/mappings/acnc-register-v1.json).
- Entries specify meaning, types, transformation/null rules, cardinality, proposed
  database/public destinations, review groups, attribution, suppression, fixture
  references and current implementation support. Proposed destinations are not
  described as deployed. Existing scalar columns were checked against portal types.
- Reconciled both pinned upstream mapping references with the observed schema.
  Preserved ambiguous other names and countries as text; F02 must qualify richer
  parsing rather than lose facts. Pilot raw values informed date, year-end and flag
  examples; the committed fixture contains invented values only.
- Added a reproducible report generator and explicit schema-drift validation.
  All 31 Python tests pass, including five new inventory/coverage checks. This is
  contract coverage, not expanded runtime transformation or public field support.
- Next: F02 schema/transformation implementation, followed by F03/F04 publication
  and public UI. Source jobs and scheduling remain deferred through F05.

### F02 complete — schema and transformations

- Parser v2 transforms all 69 ACNC organisation columns and retains per-assertion
  source values and mapping version. Invalid/unknown inputs quarantine the record.
- Added default-private register-details storage with scalar, address, calendar and
  flag constraints; browser reads exclude private source identity and require both
  projection and organisation visibility. No browser or acquisition-worker writes.
- Validation: 35 Python tests and PostgreSQL 17 migration/constraint/access checks
  using the staging migration and a minimal organisation-table test harness.
- No live migration, publication expansion or pilot replay performed. F03 remains
  responsible for approval, per-fact provenance, protected edits and suppression.

### F03 complete — review and publication for complete ACNC fields

- Added the private 62-unit publication allowlist for all 69 organisation columns,
  typed validation, full snapshots and selected transactional writes. Dates stay
  dates, false flags stay false, long text/URLs are not truncated, and source
  projections stay separate. Missing assertions never clear existing values.
- The address is one atomic merge with a full displayed diff; individual flags
  update only their own keys. Manual edits and hidden projections are protected.
- Mapping/source/target changes stale approvals. Old approvals cannot authorise
  new fields. Replays do not duplicate writes or create automatic identity links.
- Extended attribution and suppression to every review unit. Target suppression
  clears the fact across source projections and blocks restoration. Suppressing
  a required name withdraws the organisation from public view.
- Grouped review UI includes Overview, Legal, Contact, Operations, Finance and
  Governance, with eligible selection and excluded/conflicting/invalid counts.
- Validation: complete PostgreSQL 17 migration and six rollback-only SQL suites,
  36 Python tests (including manifest/allowlist agreement), route action tests,
  browser tests for group selection and atomic diffs, and clean Svelte checking.
  The isolated DB harness uses the real portal table definitions and ingestion
  migrations, with emulated auth/JWT helpers; it is not a hosted Supabase test.
- F04 public rendering and F05 retained-pilot replay remain. No live migrations,
  pilot changes or deployment were performed.

### F04 complete — public register facts and anonymous access

- Added a narrow public RPC returning the latest approved observation per source
  identity and field, with source links, licences and observation/publication dates.
  Disagreements remain separate. Superseded observations, private evidence, actor
  and internal identity fields, unpublished approvals, hidden projections and
  suppressed/withdrawn content are excluded.
- All 62 review units appear on existing organisation sections. Governance counts
  appear on Overview; Contact preserves all address lines and source role;
  Operations separates purposes, beneficiaries and operating jurisdictions;
  Finance labels year-end as a reporting calendar. False and zero remain visible.
- Source observations changed in the portal are clearly labelled. Date fields
  retain their source-reported dates; omitted address components retained from
  previous approvals are explained. Public links accept only safe HTTP(S) URLs.
- Validation includes seven PostgreSQL suites, explicit anonymous table/RPC reads,
  actual page loaders and Svelte SSR using anonymous database exports, and browser
  checks for five rendered section pages. These are local tests with emulated auth
  helpers, not a hosted deployment. No live migration or pilot replay performed.
- F05 remains: reprocess retained pilot evidence with fresh approvals and finish
  the full release gate against the deployed application.
