# Portal implementation plan

Prepared: 15 September 2026. Updated: 16 September 2026 after acquisition-code review.
Status: in progress — ACNC private staging and initial operator review implemented and tested locally; hosted deployment has not started.

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
link. Field-level differences, selected-field approval, publication, suppression,
source administration and a history UI remain outstanding. Source/run browsing
currently lists the latest 50 runs and 50 records per page.

Validation: Svelte check, production build, route regressions and rollback-only
PostgreSQL review tests passed. SQL verification used a disposable PostgreSQL 16
container with minimal auth/portal fixtures; the hosted migration chain and browser
workflow against a deployed Supabase instance remain unverified. See
[operator review setup](private-staging.md#operator-review).

Next: field-level change proposals and manual-edit protection (P10/P15), followed
by the transactional publication service (P17). Deploy and verify this review
increment on a chosen development Supabase instance before pilot use.
