# Portal implementation plan

Prepared: 15 September 2026. Updated: 23 September 2026 for the P33 execution
environment decision.
Status: P31's private registry candidate boundary and P32 directory readiness are
deployed. ACNC
acquisition, reviewed publication, complete-snapshot reconciliation,
withdrawal/redaction and guarded rollback are implemented. The monthly 23-postcode
schedule is enabled. Exact-ABN live qualification remains externally gated. The
national ABN bulk adapter is implemented locally. The next implementation phase is
the public NSW incorporated-associations search adapter, followed by candidate triage.

## Current priorities: registry seeding and directory usability

[The complete public register field coverage plan](import-field-coverage-plan.md)
(F01–F05) has passed its release gate. F02–F05 and website-v3 migrations are applied
live. The complete six-record replay is run 8; original run 6 and partial run 7
remain retained. The operator confirmed approval/publication and all follow-up
checks, including hosted signed-out access, attribution/dates, coverage,
exclusions/suppression and duplicates. See the
[v3 validation and closure report](acnc-website-normalisation.md).

Acquisition job controls and scheduling are deployed: operator queue/status UI,
bounded Python worker, fenced leases, immutable checkpoints, retry/backoff and cron
enqueueing. The restricted worker runs on AKHOME, the monthly Snowy Valleys schedule
is enabled, and P27–P30 cover reconciliation, withdrawal, rollback and a second
cycle. The remaining ACNC task is operational observation of the first scheduled
run after `2026-10-19T03:18:23Z`; it does not block new engineering.

“Fully seeded” means complete, reproducible candidate coverage for the configured
registry scopes. It does not mean that every ABN becomes a public community
organisation. Registry records first enter a private candidate layer. Inclusion,
identity and field decisions still pass through deterministic matching and operator
review. Registered address/postcode is discovery evidence, not proof of local
service delivery.

### Source implementation status

The staging, provenance, review, publication and recovery controls provide a
foundation for additional sources. Each source still needs its own adapter,
qualification, mappings and acceptance tests; the deployed ACNC worker does not
automatically acquire other providers.

| Source                                                      | Current status                                                                                                                                                                                                   | Remaining work                                                                                                                                                                                                                      |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ACNC Register                                               | CKAN worker and 23-postcode Snowy Valleys configuration deployed; [P13 bulk fallback](acnc-acquisition.md) and complete-field reviewed publication implemented; monthly hosted schedule enabled                  | Observe the first expanded scheduled job after the October 2026 due time and record operational sizing findings                                                                                                                     |
| Approved CSV files (P12)                                    | Implemented, deployed and hosted database verification passed; [CLI and verification](approved-csv-import.md)                                                                                                    | Deferred until an approved provider CSV is received; P12 remains complete                                                                                                                                                           |
| Exact-ABN Lookup (P16)                                      | [Bounded adapter implemented](exact-abn-lookup.md); live qualification pending                                                                                                                                   | Provision access GUID and approved exact-ABN set; complete live/withdrawal checks                                                                                                                                                   |
| ABN public bulk extract                                     | P33 streaming/checkpointed local-file adapter and synthetic release suite implemented; the first release will run from the approved local operator workstation, not Vercel; no real release downloaded or staged | Approve acquisition and the workstation storage boundary, qualify and run one current complete release, inspect private output, register/enable the source resource explicitly, then stage only the verified complete candidate set |
| NSW incorporated associations                               | No bulk feed; upstream scrapers assessed but no current adapter is integrated                                                                                                                                    | Build a bounded scraper over the ordinary public postcode/suburb search interface, using conservative request pacing, current markup fixtures and jurisdiction-scoped association identifiers                                       |
| Landcare, neighbourhood houses, sports and arts directories | Expansion backlog                                                                                                                                                                                                | Select pilot providers, qualify access/reuse and implement provider mappings/adapters                                                                                                                                               |
| My Community Directory                                      | Planned; not integrated                                                                                                                                                                                          | Obtain partner agreement and technical documentation before implementing the adapter                                                                                                                                                |
| ACNC AIS financial history                                  | Deferred beyond the initial release                                                                                                                                                                              | Separate adapter and reporting-period schema with explicit financial-measure definitions                                                                                                                                            |

### Next implementation sequence

1. **P31 — Registry-seed contract and candidate store — deployed.** The
   [P31 contract](registry-seed-contract.md) implements private versioned candidates,
   immutable release/part manifests, scope/completeness gates, retention, reasoned
   revision-fenced triage and bounded promotion into existing reviewed staging.
   Hosted migration `20260922051805_registry_seed_candidates` is recorded.
2. **P32 — Make a larger directory operable — deployed.** The
   [directory-readiness implementation](directory-readiness.md) adds ranked
   server-side name/alias/exact-ABN search with visibility-preserving pagination,
   plus correction of aliases, locations, document links and relationship dates.
   Hosted migration `20260922052255_directory_readiness` and Vercel production
   deployment `dpl_EgFjYVd54bVPvR25NwufmR365UhN` are verified. Scoped alias and
   relationship removal actions were added locally after the signed-in regression
   exposed those gaps; hosted verification remains. Document records remain URL-only;
   local file upload is a separate capability gap.
3. **P33 — Implement the ABN bulk seed adapter — complete locally.** The offline
   standard-library adapter streams every XML member in both official ZIP ranges,
   verifies file hashes plus XML member sequence/count/extract metadata, checkpoints
   completed parts and emits the P31 private candidate contract. Missing, changed,
   malformed, duplicate or incomplete inputs fail closed. No real release has been
   downloaded or staged. The first qualified run will execute manually on the local
   operator workstation using an approved path outside the repository; Vercel remains
   the application/review host and is not the batch runner or artifact store. See
   [the P33 guide](abn-bulk-seed.md).
4. **P34 — Implement the NSW register scraper.** Use only the ordinary unauthenticated
   postcode/suburb search flow, with conservative pacing, bounded retries,
   pagination checks, duplicate detection and markup-change shutdown. Key records
   by `(AU-NSW, association number)` and do not merge by name. Document the public
   access/reuse basis and collect only the defined public register fields.
5. **P35 — Add candidate triage and cross-source resolution.** Join only on qualified
   identifiers; present name/address similarities as review candidates. Record why
   each candidate is included, excluded, deferred or linked, and keep adjacent-area
   records private until service relevance is evidenced.
6. **P36 — Publish and maintain the registry seed.** Review a bounded first cohort,
   publish attributable records, add source/postcode/freshness/failure reporting,
   then exercise unchanged refresh, status change, withdrawal, partial-run and
   rollback paths before enabling recurring ABN and NSW collection.

P34 is the next implementation track. A qualified first P33 release can proceed as
parallel operational work without blocking the NSW adapter.
P16 live exact-ABN qualification and the first scheduled ACNC observation continue as parallel
operational tracks and do not block P31–P36.

**Decision — 23 September 2026:** use the local operator workstation for the first
qualified P33 ABN bulk release. Keep its source ZIPs, release configuration,
checkpoints and generated artifacts under an approved absolute path outside the Git
repository; the proposed default is
`/home/akeown/private/community-orgs/abr`. The workstation run is a manual,
operator-observed production acquisition. Vercel continues to host the portal only,
and Supabase continues to hold private staged candidates. A VM, Vercel Blob or other
object-store integration is not required for the first release and may be reconsidered
before unattended recurring acquisition. This execution-environment decision does
not itself approve source acquisition, the proposed filesystem path, retention or
database source enablement; record those gates before downloading or staging real
data.

**Decision — 22 September 2026:** promote national ABN bulk processing and NSW
register scraping from conditional expansion to the active registry-seeding phase.
The NSW register has no bulk feed; collection uses its ordinary public postcode or
suburb searches without bypassing access controls. Public search results and ABN
bulk records are discovery candidates, not automatic public organisations.

**Decision — 18 September 2026:** P12 is complete, deployed and verified.
Real-provider CSV onboarding is deferred at the user's request until approved CSV
information is available. It is not an active completion blocker for P12 or P16.
Coverage dependent on those exports waits. Retain the deployed importer and
synthetic fixtures; no rollback or CSV source enablement is needed. This decision
still applies to provider CSV files, but it does not defer the ABN bulk or NSW
public-search work promoted on 22 September. See the
[CSV deferral record](approved-csv-import.md#real-provider-onboarding-deferred--18-september-2026).

This sequence supersedes the original first-batch instructions below; the milestone
tables remain the broader backlog, not a completion checklist.

## Original delivery approach

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

- Pilot: Snowy Valleys LGA, plus organisations elsewhere with evidenced service
  delivery within it, as defined in the completed [P01 inclusion policy](pilot-inclusion-policy.md).
  Candidate discovery targets the documented [23 postcodes](snowy-valleys-postcode-scope.md)
  that overlap or directly border the LGA. Multi-postcode configuration and the
  rebuilt worker are deployed; the expanded acquisition has not yet run.
- First publication target: a bounded, reviewable slice of the registry-derived
  candidates, including existing records, duplicate candidates and groups without
  ABNs. Candidate acquisition may be much larger than the publication batch.
- Active seed sources: ACNC Register, the national ABN bulk extract and the NSW
  incorporated-associations public search. Approved CSV remains available for later
  providers; exact-ABN verification proceeds when access is available. No AIS
  financial-history import is included in this phase.
- Access: retain current organisation roles; add a distinct platform ingestion role.
- Publication: operators approve new records and changes during the pilot.
- UI: extend the current Svelte/Skeleton interface and navigation conventions.
- Scope: keep branches and services distinct; defer ambiguous cases until their
  mapping is resolved rather than merging on a shared name or ABN.

These defaults allow work to proceed without choosing every later feature now.

## Historical progress: offline ACNC first step

These early progress notes describe their implementation stage. Later deployment
and recovery results above supersede their operational limitations.

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

| ID  | Task                                                  | Deliverable / acceptance                                                                                                                                                              |
| --- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P01 | Write the pilot inclusion policy — complete           | [Policy v1.0](pilot-inclusion-policy.md) defines Snowy Valleys scope, categories, entity/group/service distinctions, exclusions and evidence/review rules                             |
| P02 | Fix relationship UUID conversion (gap G01) — complete | Partner search uses string IDs, excludes the current organisation and surfaces failures; browser creation succeeds                                                                    |
| P03 | Capture a development baseline                        | Record check/build results and relevant SQL test results against a disposable/local database; identify hosted migration drift before deployment                                       |
| P04 | Qualify source samples — complete                     | [Qualification record](source-sample-qualification.md): retained six-record ACNC evidence, versioned synthetic CSV/schema/manifest, and ABN access handoff                            |
| P05 | Sketch the core journeys — complete                   | [Journey sketches v1.0](core-journeys.md): import → match → field review → publish; organisation edit → conflict review; reject/withdraw → suppress, with current/proposed boundaries |

**Exit:** a representative sample, agreed working scope and reviewable workflow
sketches exist. Current application failures are distinguished from proposed work.

P04 can proceed alongside the search fix and UX sketches. Waiting for provider
access must not prevent fixture-based development, but fixtures do not substitute
for access approval or real-format validation.

### Milestone 1 — Access boundaries and schema

**Indicative effort: 1–2 weeks. Depends on P01, P04 and P05.**

| ID  | Task                                                      | Deliverable / acceptance                                                                                                                                                                                                                    |
| --- | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P06 | Define the capability matrix — complete                   | [Capability matrix v1.0](capability-matrix.md) separates public/registered readers, organisation roles, ingestion operators and platform administrators; records session, scope and P07/P08 verification rules                              |
| P07 | Implement scoped operator access — complete               | [Hosted access verification](scoped-operator-access.md): migration and application deployed; server/RPC/role/MFA checks and signed-in production boundaries verified                                                                        |
| P08 | Implement minimum organisation role management — complete | [P08 implementation and hosted verification](organisation-role-management.md): scoped assignments, hierarchy/MFA, owner safeguards and signed-in production checks passed                                                                   |
| P09 | Add private ingestion storage — complete and deployed     | [P09 storage and retention](private-ingestion-storage.md#deployment-record): private schema, source-policy raw retention, holds, preview/removal and replay-safe audit; completion/deployment recorded in commit `703a903`                  |
| P10 | Add publication and edit protection — complete            | [P10 acceptance and recovery](publication-edit-protection.md): explicit visibility, revision/manual-edit protection, publication events, suppression and importer ownership checks; local regression and hosted catalog evidence            |
| P11 | Define identifier and entity mapping — complete           | [Mapping contract v1.0](identifier-entity-mapping.md): jurisdiction-scoped identifiers, legal-entity/branch/service rules, target duplicate constraints and a UUID-preserving migration path; schema enforcement remains P14 implementation |

Before finalising migrations, compare proposed fields with actual source headers and
existing portal records. Preserve the existing `org_id` UUIDs and relationships.
Do not introduce a global unique ABN constraint across legal entities and branches
without first resolving the entity model.

P11 defines that model and its migration gates; it does not deploy identifier
tables, verified matching or branch/service publication. P14 implements the
[identity constraints and backfill](identifier-entity-mapping.md), with P16 supplying
exact-ABN verification evidence. Current CSV branch/service holds remain in place.

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

| ID  | Task                                                      | Deliverable / acceptance                                                                                                                                                                                                                          |
| --- | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P12 | Build approved CSV importer — complete and deployed       | [Importer and verification](approved-csv-import.md): validates metadata/rows, retains quarantine reasons, stages replay-safe records for reviewed publication                                                                                     |
| P13 | Adapt existing Python ACNC extractor — complete           | [P13 implementation and validation](acnc-acquisition.md): full resource/schema qualification, versioned staging records/manifests and bounded bulk CSV fallback; six-record live parity and disposable staging/replay checks passed               |
| P14 | Add deterministic matching — complete and deployed        | [Identity implementation and hosted verification](deterministic-matching.md#hosted-completion--18-september-2026): reconciled unverified backfill, canonical matching, conflict holds, approval fencing and production operator/MFA checks passed |
| P15 | Generate field-level changes — complete and deployed      | [Private dry-run reports](field-level-changes.md): six record categories, field evidence, prior observations/revisions and guarded missing-record comparisons; local and hosted SQL, production download/access and real MFA verification passed  |
| P16 | Exact-ABN adapter implemented; live qualification pending | [Pinned SOAP contract, bounded acquisition and private review evidence](exact-abn-lookup.md); unavailable access leaves verification pending                                                                                                      |
| P17 | Add transactional publication service                     | Applies an approved immutable change set, checks revisions and records exact before/after values                                                                                                                                                  |

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

### Milestone 5 — Registry seeding and measured expansion

P31–P36 above are the active registry-seeding programme. After it establishes
candidate coverage and operating cost, schedule further sources and domain work in
the order supported by measured gaps and user feedback:

| Work                                                                | Dependency / reason                                                        |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Landcare, neighbourhood houses and selected sports/arts directories | Provider-specific terms; supports informal groups and local services       |
| My Community Directory adapter                                      | Partner agreement and technical documentation                              |
| Role requests and representative claims                             | Agreed verification policy and tested request/review permissions           |
| Social media, insurance and auditor UI (G07)                        | Actual use cases and suitable structured forms                             |
| Governance/programs/accreditation/assets/metrics screens (G06)      | Defined domain workflows; prioritise services if directory users need them |
| Global relationship list/detail routes (G03)                        | Demonstrated need beyond organisation-specific navigation                  |
| AIS financial history (G08)                                         | Period-aware schema and explicit financial-measure definitions             |
| Geocoding and service-area improvements (G09)                       | Address roles, provider terms and geographic requirements                  |
| Reports (G12)                                                       | Agreed questions and sufficiently complete data                            |
| Broader visual redesign                                             | Evidence from working user journeys and content                            |
| ABAC (G11)                                                          | Specific access requirements that current roles cannot reasonably express  |

## Original first implementation batch

Historical sequencing is retained here for context. Use the current priorities
and next implementation sequence above for new work.

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
| Seed scope       | Canonical postcode/suburb scope, source release identity and reproducible candidate counts         |
| Completeness     | Every ABN release part and NSW results page accounted for; partial/failed runs cannot reconcile    |
| Scraper safety   | Bounded rate/retries, no access-control bypass, fixture-backed parsing and markup-change shutdown  |
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

| Decision                         | Needed by                     | Proposed default                                                                                                                  |
| -------------------------------- | ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Pilot geography/categories       | P01 — resolved                | [Policy v1.0](pilot-inclusion-policy.md): Snowy Valleys LGA or evidenced service delivery within it; defined community categories |
| Legal entity/group/service model | P11                           | Separate identities/scopes; never merge merely because ABNs are shared                                                            |
| Who approves publication         | P06–P07                       | Explicitly appointed platform operators                                                                                           |
| Custom roles or ABAC             | No pilot dependency           | Retain organisation roles and add a narrow platform capability                                                                    |
| Source permissions/credentials   | Each live adapter/publication | Disable sources whose access or reuse remains unresolved                                                                          |
| Financial history                | Expansion                     | Exclude AIS financial import from pilot                                                                                           |
| Hosting and operating budget     | P26                           | Bounded scheduled worker selected after measurements                                                                              |
| Representative claims            | Claim workflow                | Reviewed claim; imported records confer no account ownership                                                                      |

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

## Retained suppression redaction — 20 September 2026

Implemented P28 retained-copy cleanup for suppression and withdrawal. Suppression
now redacts matching values from retained source versions, run envelopes, acquisition
checkpoints and private approval/publication snapshots, and records a private
`ingestion.retained_evidence_redaction_events` audit row with copy counts, reason and
operator. Staging and worker checkpoint entry points reapply redaction for already
suppressed source identities, preventing later acquisition or replay from restoring
withdrawn content. Reprocessing tests now require replay from redacted parent
evidence to fail instead of proving suppression survives a raw-evidence replay.

Validation: generated ingestion SQL regression passed against disposable PostgreSQL
16, including retained suppression redaction, complete-snapshot reconciliation,
retention, acquisition, website normalisation and replay suites. External backups,
object stores and deployed database verification remain operational rollout checks,
not local schema behavior.

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

### F05 complete — retained-pilot publication and verification, 17 September 2026

- V3 website normalisation and all F02–F05 migrations are applied live; run 8 is
  complete with six accepted records and zero quarantine. Runs 6 and 7 remain
  retained with their original evidence and observation time.
- The operator confirmed fresh approval/publication and completion of all
  post-publication checks. This supersedes pending release-gate statements in the
  earlier progress entries above; their test and staging results remain historical.
- The public route guard now permits signed-out organisation reads while retaining
  protected submissions and admin routes. Local HTTP, regression and type checks
  passed, followed by the operator’s confirmation of post-publication verification.
- F01–F05 are complete. Acquisition job controls and scheduling are next; no jobs
  are enabled by this documentation update.

### Acquisition job controls and scheduling — 17 September 2026

Implemented the local P26 increment in `/admin/ingestion/jobs`, private database
queue RPCs, `ingestion.worker` and the existing cron route. Platform administrators
configure postcode/licence and opt into a schedule; operators queue and inspect
jobs. Duplicate requests reuse active jobs. Approval/configuration changes fence
old workers; completed acquisition checkpoints survive worker interruption and
staging is atomic with job completion. Partial/failed runs retain private evidence
and cannot publish. Optional systemd deployment examples poll one job at a time.

Validation: 51 Python tests, disposable PostgreSQL ingestion/job suites, the actual
Python worker with a restricted local database login and fixture HTTP responses,
route/cron regressions, Svelte check, targeted ESLint and production build passed.
See [acquisition jobs](acquisition-jobs.md) for deployment instructions and limits.
P26 awaits hosting and live verification; P27/P30 still require their remaining
reconciliation and second-cycle release checks. No live jobs or schedules enabled.

### Acquisition database deployment — 17 September 2026

Applied `acquisition_jobs` (`20260917014227`) and `acquisition_worker_login`
(`20260917014304`) to project `gqltsfijginclwszrcfj`. The LOGIN
`community_orgs_acquisition` has only the staging-worker membership, NOINHERIT,
no superuser/BYPASSRLS and a two-connection limit. Hosted privilege inspection passed; actual worker-login connectivity remains
unverified. Jobs/configurations remain empty. Password
provisioning and service installation await the worker-host selection; application
deployment and a first manual live refresh remain pending. See the current
[deployment record](acquisition-jobs.md#deployment-record).

### AKHOME worker provisioning — 17 September 2026

Installed `community-orgs-acquisition-worker` in Docker Desktop on AKHOME (WSL2).
It polls once a minute, has `unless-stopped` restart behaviour, and uses a
restricted password file outside Git. The project session pooler provides IPv4
connectivity with verified Supabase TLS. A real password-authenticated connection
assumed `ingestion_worker` and returned an idle queue; hosted jobs/configurations
remain empty. Docker Desktop must be running and AKHOME awake/online. See
[operating the worker](acquisition-jobs.md#operating-the-akhome-worker).

Next: application deployment, pilot acquisition configuration and the first manual
live refresh. Acquisition schedules remain off and publication remains explicit.

### First live acquisition and portal deployment attempt — 17 September 2026

Configured the approved postcode 2730 pilot with no schedule and queued manual job
`5e68af3a-db56-47a1-ba49-b4166ef94219` through the management API. AKHOME processed
it in one attempt: run **9**, six accepted records, zero quarantine and no errors.
This validates the deployed queue/worker/staging path, not browser form submission.
No publication was requested.

The production portal deployment was rejected before upload by automatic approval
review because the source bundle exceeds its 200,000-byte limit. The existing
production site is unchanged. CLI credentials have expired; approval of a CLI
deployment and renewed `vercel login` were requested. Application deployment and
hosted job-form checks remain outstanding. See [deployment record](acquisition-jobs.md#deployment-record).

### Production portal deployment — 17 September 2026

After the user renewed the CLI login, deployed the current portal source to the
existing production project. Deployment `dpl_9tF1mk7odunPnGwdPXjwjzf4mng3` is READY
and aliased to `https://community-orgs-portal.vercel.app`. This resolves the earlier
deployment blocker. Public organisation pages returned 200, protected acquisition
and review pages redirected to sign-in, and unauthenticated cron access returned 401. Run 9 remains complete with six accepted records, with scheduling off.

The live worker/queue path was tested through the management API. Signed-in browser
form submission remains an operator check. This was a working-tree CLI deployment;
the uncommitted changes must be included before any later Git-triggered deployment.

### Operator recovery checks confirmed — 17 September 2026

The operator recorded Pass for worker stopped/restarted, source paused with queued
work, and a fresh job after re-enablement. Read-only database inspection confirmed
runs **11** and **12** complete with six accepted records, zero quarantine and one
attempt each; the paused job remains cancelled with no staged run. The source is
enabled and scheduling remains Off. See [operator recovery checks](acquisition-jobs.md#operator-recovery-checks).

These close the signed-in job-control checks. They do not demonstrate recovery
from interruption of an already running acquisition. Controlled failure/replay
verification remains the next step; P27/P30 are not marked complete.

### Controlled recovery verification complete — 17 September 2026

Ran `scripts/test-acquisition-recovery.py` on an isolated Docker network with a
fresh PostgreSQL 16 database, synthetic source responses and the real Python
worker/database RPCs. Both SIGKILL scenarios recovered on attempt 2 with exactly
one staged run; checkpoint recovery made no source requests. Changed-data refresh
preserved a manual correction, field suppression and whole-record withdrawal.
Failed/partial source runs preserved public data and existing versions; an eligible
partial-run approval was rejected by the completion gate. Existing ingestion SQL
suites also passed. All temporary containers/network were removed.

The [controlled recovery report](acquisition-jobs.md#controlled-recovery-results--17-september-2026)
records the exact evidence and test-only lease-expiry acceleration. This closes
the four requested recovery scenarios. No production data, deployment or schedule
was changed. Next is an explicit refresh-cadence decision and first scheduled-job
verification; P27 reconciliation/closure semantics remain a distinct implementation
concern and are not marked complete by these checks.

### P02 complete — relationship partner search, 17 September 2026

Organisation UUIDs now remain strings from the page through the form and search
exclusion filter. Lookup failures are visible; empty results have a distinct
message. Editing the search clears the selected partner, and late responses
cannot restore stale results or override a newer search.

Validation: Svelte check, targeted ESLint, production build and
`npm run test:relationships` passed. The browser regression exercises the actual
page, form, picker and server action with synthetic Supabase transport/storage
and a test form-enhancement adapter. It covers current-organisation exclusion,
query/network failures, empty results, stale responses, selection reset, successful
creation and rejection without editor access. It does not verify hosted database
RLS or the production SvelteKit enhancement runtime. No deployment or hosted data
changes were made. The browser script requires Playwright and installed Chromium;
use `PLAYWRIGHT_MODULE` to point to an existing Playwright module when it is not
installed locally, as with the other browser regression scripts.

### P04 complete — source sample qualification, 17 September 2026

[Qualification record](source-sample-qualification.md) consolidates the exact ACNC
resource/revision, recorded licence, attribution specification, schema and retained
six-record observation. Added a nine-record synthetic CSV with versioned schema,
file hashes, explicit internal-development use basis and expected candidate/hold/
quarantine outcomes. ACNC mapping coverage and CSV integrity checks pass.

Official ABN registration, agreement and response/method documentation were checked;
the access handoff records owner registration/GUID provisioning, withdrawal handling
and the current recommended exact-ABN operation (`SearchByABNv202001`) for P16.
No registration or agreement acceptance was submitted. Credentials and live
verification remain pending. P12 still owns the importer and qualification of a real
approved provider export; the synthetic fixture grants no provider permissions.
No hosted data, source enablement, schedule or deployment changed.

### P05 complete — core journey sketches, 17 September 2026

[Journey sketches v1.0](core-journeys.md) documents import → match → field review
→ publish, organisation edit → conflict review, and reject/withdraw → suppress.
Each journey has a decision flow, low-fidelity screen sketches, actor boundaries,
failure/retry outcomes and walkthrough acceptance scenarios grounded in P01/P04.
Existing routes and controls are distinguished from proposed CSV import, conflict
resolution and broader reconciliation work. Rejection, field suppression and
whole-organisation withdrawal have explicit, different effects.

Validation: checked the sketches against current route actions, review components,
authorization and field-preview rules; all 11 local reference links resolve and
the three Mermaid blocks have balanced fences. Documentation-only change; no
application tests, hosted operations or deployment were needed. P05 completion
does not mark the later implementation milestones complete.

### P06 complete — capability matrix, 17 September 2026

[Capability matrix v1.0](capability-matrix.md) defines organisation and global
authority, including the retained moderator role, registered-reader access,
operator candidate visibility and platform administrators’ effective owner access.
It records conditional MFA, role hierarchy/actor rules, controlled appointment
requirements, machine identities and publication/removal boundaries.

Repository evidence is linked separately from P07/P08 acceptance scenarios.
Appointment audit history and ownership-continuity safeguards are explicitly
identified as incomplete rather than implied by role names. Historical role/ABAC
examples now point to the pilot contract. Validation: local documentation links
and diff whitespace checked; no runtime changes or application tests required.
P07/P08 remain separate implementation/verification milestones.

### P07 complete locally — scoped operator access, 17 September 2026

[Access verification](scoped-operator-access.md) records the operator/platform
administrator boundary and its server/database tests. The Admin hub now checks
its capability independently with private caching; the hook shares the same
route gate. Organisation admin/owner assignments confer no global access.

Tests against real access migrations uncovered a legacy SELECT policy that
allowed expired organisation assignments to read private base rows. Migration
`20260917063242_scoped_access_expiry.sql` replaces it with the expiry-aware helper.
Active organisation access and independent platform appointments are preserved.

Validation: five SQL suites pass against 33 unmodified migrations in disposable
PostGIS 17, including every global task RPC, role scope, conditional MFA,
revocation and reviewed publication. New and existing route regressions, Svelte
check, targeted ESLint and production build pass. Auth scaffolding is emulated;
no hosted verification or deployment was performed. Deploy the migration and
application before claiming hosted closure. P08 remains separate work.

### P07 deployed and verified — 17 September 2026

Applied `scoped_access_expiry` to hosted Supabase as **20260917063242** and aligned
the repository migration filename with that version. Production deployment
**dpl_9PPf4QrDxtVqyMYN7zQjB9bzDQZt** is READY at
[community-orgs-portal.vercel.app](https://community-orgs-portal.vercel.app).

The hosted rollback-only P07 SQL suite passed, including role scope, direct RPC
denials, private grants, conditional MFA and revocation. Real signed-in HTTP
checks with temporary owner/operator/administrator accounts verified both page
and action boundaries. Reusing sessions after appointment revocation and role
expiry denied Admin/RPC access and hid the private organisation through PostgREST.
All temporary accounts, assignments and organisations were removed; no production
source, schedule or publication changed. See [hosted verification](scoped-operator-access.md).

This closes the deployment/verification work left pending in the local entry
above. P07 is complete; P08 remains separate. The working-tree deployment must
be preserved in Git before a later Git-triggered release.

### P08 complete locally — organisation role management, 17 September 2026

Added the organisation **Manage access** page to list assignments and grant/revoke
existing roles through authorised RPCs. Account settings exposes the caller's own
account ID for sharing with a manager. Reads and mutations check the exact
organisation, registered session and conditional MFA. The database preserves
actor identity, rejects changes above the actor's hierarchy and denies direct
browser assignment writes.

Self-revocation is blocked; owner grants cannot expire and an active owner cannot
be revoked without another non-expiring owner. Organisation locks serialise role
changes. Concurrent revocation testing confirmed one owner remains. Existing
ownerless imports and legacy expiring assignments are not automatically repaired.

Validation: seven SQL suites against 34 unmodified migrations in disposable
PostGIS 17, concurrent owner revocations, route/action and Svelte rendering tests,
P07 route regressions, Svelte check, targeted ESLint and production build pass.
See [P08 evidence and deployment steps](organisation-role-management.md).
No hosted migration or application deployment was performed; signed-in production
verification remains pending before hosted closure.

### P08 deployed and verified — 17 September 2026

Applied `organisation_role_management` as **20260917065322** and aligned the local
migration filename. Production deployment **dpl_HEtHzw9KTmdB8WZYj58qE7Xhv2eH** is
READY at [the portal](https://community-orgs-portal.vercel.app).

The hosted rollback-only SQL suite passed. Real signed-in HTTP checks verified
scoped assignment reads, grants, replay, revocation, actual audit identity and
immediate same-session loss of access. Real TOTP verification confirmed AAL1 denial
and AAL2 reads/mutations. Owner self-revocation was refused and a grant-first
ownership transfer succeeded. All temporary accounts, factors, organisations and
synthetic role audit rows were removed; no pilot acquisition or publication changed.

[P08 hosted evidence](organisation-role-management.md#hosted-verification--17-september-2026)
closes the deployment and verification work in the local entry above. P08 is
complete. Preserve the deployed working-tree changes before a later Git release.

### P09 complete locally — private ingestion storage, 17 September 2026

[P09 storage and retention](private-ingestion-storage.md) maps sources, runs,
versioned identities, links, assertions and change sets to the existing private
schema. Added source-specific raw snapshot retention with default holds, preview,
transactional removal across envelopes/payloads/checkpoints and private removal
audit. Original hashes preserve immutable run replay after expiry; fresh observations
retain shared raw objects and active jobs hold cleanup for recovery.

Raw objects remain private JSONB for the bounded pilot. Assertions, source-value
provenance and publication audit are retained separately; this is not complete
personal-data erasure. No source retention period is assumed or seeded.

Validation: 35 real migrations, eight SQL access/publication/storage suites,
concurrent owner-revocation checks and all 51 Python ingestion tests passed in local
disposable environments. The full ingestion SQL suites and real worker crash/recovery
checks also passed on PostgreSQL 16. See the P09 record for deployment and forward repair.
At this local implementation stage, no hosted migration, raw removal, source
enablement or schedule change was performed. The deployment record below supersedes
the pending hosted status from this stage.

### P09 completion and deployment recorded — 17 September 2026

Commit `703a903` records **“P09 completed and deployed”**. P09 is therefore recorded
as complete and deployed, superseding the earlier local-only status. The
[storage deployment record](private-ingestion-storage.md#deployment-record) identifies
the migration and available hosted verification scripts. Detailed hosted execution
output is not retained in the repository; the documented local test results above
remain distinct from this completion/deployment record.

Documentation reconciled on 18 September 2026; no database operation or deployment
was performed by this correction. P12, the approved CSV importer, remains the next
implementation task.

### P12 complete locally — approved CSV importer, 18 September 2026

Added a bounded offline CSV command, private qualification-gated staging RPC and
operator workflow integration through existing review/publication controls. The
P04 fixture yields two candidates, four holds and three quarantined rows with
reasons. Source/resource identity, raw evidence, timestamps, hashes and scoped
incorporation identifiers are retained. Partial and synthetic files cannot publish;
clean approved files require explicit identity review, field approval and publication.

Validation: 59 Python tests, 36 migrations in disposable PostGIS 17, eight existing
SQL suites, CSV integration and concurrent owner-revocation checks passed.
See [P12 implementation and operation](approved-csv-import.md). No hosted migration,
source enablement, real provider qualification or deployment was performed.

### P12 deployed and verified — 18 September 2026

Applied `approved_csv_import` as **20260917230927** to `gqltsfijginclwszrcfj` after
explicit user approval. Hosted rollback-only staging/review/publication and replay
checks passed; private function grants and cleanup were verified. Eight retained
runs, eight publications, seven organisations, existing source registrations and
scheduling-off state are unchanged. See [hosted evidence](approved-csv-import.md#hosted-deployment-and-verification--18-september-2026)
for management-connection versus worker-role test coverage. Real export qualification
awaits a provider file and access/reuse evidence; no real CSV source was enabled.

### P10 complete — publication and edit protection, 18 September 2026

[P10 acceptance and recovery](publication-edit-protection.md) consolidates the
existing protections for all 62 ACNC review units and the three mapped CSV fields.
Private staging/approval, explicit publication visibility, immutable snapshots,
manual protection, publication events, persistent suppression and importer
ownership safeguards satisfy the current P10 scope. No new schema or application
behaviour was needed.

Expanded the full-migration disposable runner to include seven existing staging,
field-protection, complete-field, public-fact and replay suites. Updated the legacy
complete-field MFA fixture to enroll a factor when running against the real helper.
Validation passed: 36 unmodified migrations, 15 SQL suites, CSV integration,
concurrent owner-revocation checks, review route tests and attribution validation.

Read-only hosted checks confirmed the migration history, 62 mappings, enabled
protection/withdrawal/owner triggers and private audit-table grants. Existing F05
operator/browser and P12 hosted behaviour evidence is linked in the P10 record;
no new hosted publication or browser test was performed. No deployment or hosted
mutation was required. Forward repair is documented; guarded committed-change
rollback remains P29, and unsuppression/conflict overrides remain separate work.

### P11 complete — identifier and entity mapping, 18 September 2026

[Mapping contract v1.0](identifier-entity-mapping.md) defines jurisdiction-scoped
text identifiers, verification versus registry status, legal entities, independent
groups, branches and service destinations. Canonical verified-holder constraints
prevent duplicate legal identity without imposing global uniqueness on legacy ABN
fields. Conflicting identifiers and ambiguous scope require review.

The migration path inventories existing data, preserves UUIDs and references,
backfills unverified evidence, and gates canonical matching on reviewed conflicts.
It includes concurrency/replay acceptance cases and forward repair. Validation:
checked the current schema, importer, source fixtures and publication constraints,
local reference links and diff whitespace. This completes P11's definition scope;
P14 implements the schema/matcher and P16 provides exact-ABN evidence. No migration,
hosted data change or deployment was performed; CSV branch/service holds remain.

### P13 complete — ACNC acquisition and bulk fallback, 18 September 2026

[Acquisition implementation and validation](acnc-acquisition.md) completes resource/
schema qualification, versioned records and acquisition manifests, and an explicit
bounded direct CSV fallback. Live CKAN schema checks now cover all 70 mapped
columns. Bulk CSV preserves its separate resource identity and never fabricates
CKAN IDs or automatically merges on ABN.

The live bulk scan read 66,315 rows and selected six postcode-2730 records with no
quarantine; their typed assertions matched a fresh six-record CKAN acquisition.
Private outputs retain source hashes and diagnostics. No real data was staged or
published. Validation: 74 Python tests, mapping coverage, 36 migrations and 16 SQL
suites plus CSV integration/owner concurrency, and real worker recovery checks in
disposable environments passed. See the linked contact-free validation summary.

The existing deployed worker and scheduling are unchanged. Stricter CKAN checks
require a worker rebuild to take effect there. Bulk source onboarding, full-field
publication allowlisting, broader snapshot reconciliation and the refresh-cadence
decision remain separate from completed P13 acquisition/staging.

### P14 implemented locally — deterministic identity, 18 September 2026

[Implementation and rollout](deterministic-matching.md) adds private organisation
classification, identifier claims/reservations, audited operator verification,
branch-parent evidence and exclusive organisation/service source links. Legacy
values backfill as unverified evidence without changing UUIDs or public fields.
The queue shows deterministic matches or holds; source links cannot conceal
conflicting verified identifiers. Approval/publication recheck identity revisions
under locks, and manual identifier edits dispute matching evidence.

Validation: 37 migrations, 17 SQL suites, CSV integration, concurrent holder and
owner checks, Svelte check, review-route regression, targeted ESLint and production
build passed locally. Reservations survive disputes/withdrawal; checksum-invalid
synthetic ABNs never verify. Branch/service publication holds remain. Canonical
verification is an explicit evidenced operator RPC; P16 lookup acquisition remains
separate. Identity maintenance has RPCs and a private inventory, not a new browser
editor. Pilot-wide identity revisions conservatively invalidate pending approvals.

The read-only inventory and rollout guide are ready. Hosted inventory, reviewed
legacy reconciliation and migration/application deployment have not occurred;
P14 is not marked deployed or fully closed. No live identity, publication or
schedule changed.

### P14 complete and deployed — 18 September 2026

After explicit user approval, applied **20260918021340** to hosted Supabase and
released production deployment **dpl_B3vfvNpga76joKAEiyK5rery8wwW**. The hosted
rollback-only P14 suite and real signed-in operator/non-operator/MFA checks passed.
All temporary accounts, sessions, factors and appointments were removed.

The private inventory and reviewed legacy backfill found seven single-row legal
records with no ABN collisions or source-assertion mismatches. Six real ABNs are
checksum-valid but remain unverified; the existing synthetic all-zero ABN is
invalid. Classifications remain unknown and no canonical holder was fabricated.
This reconciliation decision is audited privately. Pre/post/final fingerprints
confirm existing UUIDs, public data, links, permissions, publications and
suppressions are unchanged. Scheduling remains Off.

[Hosted completion evidence](deterministic-matching.md#hosted-completion--18-september-2026)
closes the local-only entry above. P14 is complete within the organisation matching
scope; branch/service publication and P16 registry acquisition retain their own
gates. No live source publication or registry verification was performed.

### P29/P30 implemented locally — guarded rollback and second-cycle validation, 20 September 2026

Added a private rollback ledger, per-field rollback events and operator RPCs for
guarded import rollback. `community_orgs.rollback_ingestion_publication` restores
only fields whose current value and `field_state` revision still match the
publication snapshot; later human edits remain untouched and are queued as
private conflicts through `community_orgs.ingestion_rollback_queue`. Import-created
targets are hidden only when every published field still passes its guard.

The rollback-only P29/P30 suite demonstrates unchanged version replay, a legitimate
second-cycle source change, a manual edit conflict, failed-source non-publication
and withdrawal replay suppression. It is wired into the disposable ingestion SQL
runner after P27/P28. Validation: the generated ingestion bundle passed through
`scripts/test-acquisition-recovery.py`'s `full_ingestion_sql_suites` checkpoint.
The broader worker-crash portion of that script returned `worker_error` after the
SQL suites had passed and was not used as P29/P30 evidence. No hosted migration,
publication, source configuration or deployment was performed.
