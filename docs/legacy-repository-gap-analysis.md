# Legacy repositories → current portal gap analysis

Reviewed: 21 September 2026. Scope: source-code comparison, not a live service audit.

The main remaining parity gaps are **NSW associations acquisition, geographic ABN
discovery, integrated ABN review/publication, cross-source coverage reporting and
tabular exports**. The current portal already has a substantially more developed
ACNC ingestion and review workflow than either predecessor.

Neither supplied repository contains a Svelte frontend or a complete application
UI. `orgs-sveltekit-etl` is a Flask/Python service despite its name;
`orgs-data-manager` contains Python scripts, database prototypes, a TypeScript
scraper experiment and an HTML capture. Consequently, this review can establish
data/workflow parity and identify current UI omissions, but cannot establish
visual parity with an earlier app. Previous screens would require another source.

## Evidence and interpretation

| Repository | Reviewed revision |
| --- | --- |
| Current working tree, initially clean | `6276f15ddfa6872c50c2c6028667e892328681db` |
| [orgs-sveltekit-etl][etl] | `2676fdcc620e9a1c8beeacf587a8bcf688aa35c9` |
| [orgs-data-manager][manager] | `dea271215b267097bc4364f562f62e784b2e1294` |

Both upstream default branches were freshly cloned and their tracked files
inventoried. Their revisions match the earlier
[acquisition code assessment](acquisition-code-assessment.md). This document
updates the comparison against the considerably newer portal implementation;
it does not replace that assessment or the historical
[documentation-to-code review](gap-analysis.md).

Evidence comes from extractors, Flask routes, transformations, loaders, model
definitions, current Python acquisition code, Svelte routes/actions, components
and migrations. “Missing” means no implementation was found in the reviewed
tree. Legacy code existence does not prove successful execution against today's
registries. Model definitions and sample loaders are distinguished from working
product features. Prior deployment evidence is attributed to project documents,
not independently re-certified here. No registry calls, database changes or
application modifications were performed; application tests were not rerun for
this documentation-only review.

## Data management and operator workflow gaps

Priorities below are proposed relative priorities, not changes to `todo.txt`.

| ID / priority | Earlier capability and evidence | Current implementation | Remaining gap and completion criteria |
| --- | --- | --- | --- |
| D01 — High | NSW register search, pagination and detail extraction in [ETL NSW extractor][nsw] and [manager NSW worker][manager-nsw]. | No NSW adapter under [current adapters](../tools/ingestion/python/ingestion/adapters). Generic approved CSV staging exists, but the NSW register has no bulk feed. | **Missing source integration.** Qualify and implement a bounded NSW register scraper; map association number, name, type, native status/dates and office address into reviewed assertions. Demonstrate pagination, detail parsing, partial failures, provenance and publication with no automatic name-based identity merge. Confirm automated-access and reuse conditions before enabling collection, and stop safely if the register structure changes. |
| D02 — High | Both [ETL ABN extractor][abn] and [manager ABN worker][manager-abn] search charities by state/postcode and then retrieve individual ABNs. | [Exact-ABN adapter](../tools/ingestion/python/ingestion/adapters/abn.py) accepts supplied identifiers; no geographic discovery implementation. | **Missing discovery mode.** If needed for measured coverage gaps, add bounded, qualified geographic discovery and preserve candidate evidence. Legacy `SearchByCharity` is charity discovery, not a census of every community organisation. National bulk ABN processing is a separate expansion, absent from both predecessors too. |
| D03 — High | [ETL API][api] provides `/lookup/abn/<abn_number>` and source sync routes; ABN transformation/loading attempts to carry registry detail into stored records. | [Exact-ABN command](../tools/ingestion/python/ingestion/exact_abn.py) retains private evidence; [P16](exact-abn-lookup.md) requires operator evidence review. The [queued worker](../tools/ingestion/python/ingestion/worker.py) runs ACNC acquisition. | **Partial implementation plus pending qualification.** Live ABN qualification is still pending; the adapter itself exists. No equivalent queued/browser lookup or complete ABN fact staging/publication flow was found. Add these only after qualification, preserving repeated values, source dates, review and retention controls. Existing manual legal fields are not automatic ABN enrichment. |
| D04 — Medium | [ETL API][api] supports source/state/postcode requests, CSV postcode upload, and a concurrent three-source batch. [Manager configuration][localities] supplies suburb/state/postcode tuples. | [Job actions](../src/routes/admin/ingestion/jobs/+page.server.ts) configure 1–50 unique postcodes and schedule ACNC; [job UI](../src/routes/admin/ingestion/jobs/+page.svelte) accepts pasted postcode lists. | **Partial orchestration parity.** No multi-provider batch, postcode-file upload, or locality-tuple management UI. Extend jobs with explicit provider/scope contracts once another provider is ready. File upload is an optional convenience: cohort entry already works. Do not report multi-postcode acquisition itself as missing. |
| D05 — Medium | [ETL API][api] returns source counts per postcode, failed-postcode lists and cross-source match totals; [manager batch][manager-main] writes missing-result summaries. | Job/run status and [change-report download](../src/routes/admin/ingestion/report/+server.ts) exist. [Reports page](../src/routes/reports/+page.svelte) remains a placeholder. | **Partial reporting.** No comparable consolidated source-by-locality coverage/overlap dashboard was found. Add comparable-scope counts, unmatched candidates, failure/empty distinctions and drill-down links. Coverage reports should describe the acquisition scope, not infer service availability from postal addresses. |
| D06 — Medium | [ETL CSV writer][csv-writer] exports merged records; [manager batch][manager-main] exports source CSVs. | Operator report download is JSON describing ingestion changes; private acquisition artifacts also exist. | **Missing equivalent tabular export.** Define an authorised source/approved-record CSV export with source, observation date and field provenance. A run-change JSON download is already implemented, but serves a different purpose. Keep private evidence out of public exports and apply existing suppression rules. |
| D07 — Medium | [Manager CSV cleaner][csv-cleaner] and its [SQL import][csv-sql] handle a particular legacy ABN CSV shape. | [Approved CSV importer](../tools/ingestion/python/ingestion/approved_csv.py) implements a qualified portal schema; [onboarding documentation](approved-csv-import.md) says real-provider onboarding is pending. | **Partial format compatibility.** Generic CSV import is complete; direct ingestion of the old ABN/NSW extracts is not established. Create an explicit conversion contract for each approved legacy file, with identifier/date/nested-value preservation and review. Do not treat a historical CSV as a current register snapshot. Browser organisation-file upload is absent, but was not a supplied legacy frontend feature. |
| D08 — Low / conditional | [ETL ACNC service][acnc] offers name search and exact-ABN lookup in addition to geographic acquisition. | [Current extractor](../tools/ingestion/python/ingestion/adapters/acnc.py) supports explicit town/state/postcode/ABN filters; the operator acquisition page exposes postcode cohorts. | **Partial ad-hoc lookup workflow.** Exact-ABN filtering is not missing at adapter level. No equivalent ACNC name-search helper or operator name/ABN acquisition form was found. Add if support/research workflows need targeted acquisition outside configured cohorts. |

### Field-level implications

| Field family | Assessment |
| --- | --- |
| ACNC names, website, establishment/registration dates, charity size, responsible-person count, year-end calendar, address, operating jurisdictions and classifications | Already covered by the [ACNC field inventory](acnc-field-coverage.md), [publication migration](../supabase/migrations/20260916080000_complete_field_publication.sql) and [register-facts component](../src/components/organisations/RegisterFacts.svelte). Do not re-add these as missing just because the original manual forms are narrower. |
| ABN status/effective dates, replacement/current indicators, entity classification, GST, DGR, names, address and concession details | The exact lookup retains the parsed entity tree privately, including repeated values. This is not equivalent to typed, reviewed public ABN observations or a registry-history UI. D03 needs a destination/visibility contract; avoid claiming the adapter discards all these values. |
| NSW association identity, registration/removal status and dates, registered office | Manual legal/contact fields cover some concepts, but imported NSW observations, native identity and provenance remain D01 work. |
| Financial history | Current finance records and ACNC year-end calendars are not AIS financial time series. Neither predecessor supplies a complete AIS pipeline; this is a separate backlog item, not a lost legacy feature. |

## Current UI/UX omissions

These are source-level workflow findings. No browser-based accessibility, visual,
responsive-layout or usability evaluation was performed. “Legacy model” below
means a [manager database declaration][models], not proof of an earlier screen.

| ID / proposed priority | Finding and evidence | Basis / practical completion |
| --- | --- | --- |
| U01 — High | [Directory loader](../src/routes/organisations/+page.server.ts) and [page](../src/routes/organisations/+page.svelte) provide alphabetical pagination and creation, without directory search/filter controls. | **Current product opportunity**, not proven UI regression. Add server-side name/alias/ABN search and useful geographic/source filters. The relationship partner picker is not a directory search workflow. This becomes more valuable as imported coverage grows. |
| U02 — Medium | Governance, programs/services, assets/resources, accreditation and performance metrics appear in legacy models and current schema, but lack dedicated current management screens. The [overview loader](../src/routes/organisations/[id]/+page.server.ts) fetches the first four. | **Legacy model → missing full workflows.** Build read/edit journeys for prioritised domains. Governance is partially surfaced through published ACNC responsible-person counts; that does not provide board composition, constitution or governance editing. |
| U03 — Medium | Legacy/current field definitions include social media, insurance details and auditor details; [validation](../src/lib/server/validation.ts) accepts them, but corresponding [contact](../src/components/forms/ContactForm.svelte), [legal](../src/components/forms/LegalForm.svelte) and [finance](../src/components/forms/FinancialForm.svelte) controls are absent. | **Field-level UI gap.** Define structured inputs, display and visibility rules; confirm retained JSON shapes before exposing them. |
| U04 — Medium | [Overview actions](../src/routes/organisations/[id]/+page.server.ts) add aliases; [legal actions](../src/routes/organisations/[id]/legal/+page.server.ts) add/delete document links; [operations actions](../src/routes/organisations/[id]/operations/+page.server.ts) add/delete locations; [relationship actions](../src/routes/organisations/[id]/relationships/+page.server.ts) create relationships. Existing-item edit actions are absent for these records. | **Current workflow incompleteness.** Add corrections and relationship end-date editing. Relationship partners are persisted as names, so linked identity remains a separate model decision. These are not established legacy frontend regressions. |
| U05 — Medium | [Access actions](../src/routes/organisations/[id]/access/+page.server.ts) implement role grant/revoke using account UUIDs. Request/review screens, an account picker/invitation journey and organisation membership-record management are absent. | **Partial access UX / legacy models.** Preserve the completed assignment workflow; prioritise request/review and understandable account selection. `org_members` data is distinct from an authorization assignment. Custom role builders and platform appointment UI are separate scope choices. |
| U06 — Medium | Reports is a placeholder, while ingestion jobs/review/source approval pages exist. | **Current operator UX gap linked to D05/D06.** Build coverage/reporting around existing run data; do not recreate Admin as though it were still an empty page. |

## Capabilities already present or deliberately replaced

- **ACNC acquisition and regional scope:** API acquisition, bulk fallback,
  versioned transformations and the expanded cohort exist. See
  [worker package](../tools/ingestion/python/README.md) and
  [Snowy Valleys scope](snowy-valleys-postcode-scope.md).
- **Scheduling and recovery:** the [job migration](../supabase/migrations/20260917030000_acquisition_jobs.sql),
  worker and [cron](../src/routes/api/cron/+server.ts) implement durable jobs,
  leases/checkpoints and scheduling. `todo.txt` records the first scheduled cohort
  enqueue as due after `2026-10-19T03:18:23Z`; observing it is an operational
  follow-up, not missing scheduler code.
- **Review and publication:** private staging, deterministic candidate matching,
  selected-field approval, public attribution and manual-edit protection exist.
  See [review actions](../src/routes/admin/ingestion/+page.server.ts) and
  [matching contract](deterministic-matching.md).
- **Reconciliation and rollback:** checked-in migrations implement
  [complete-snapshot reconciliation](../supabase/migrations/20260920010000_complete_snapshot_reconciliation.sql),
  [retained-evidence redaction](../supabase/migrations/20260920020000_retained_suppression_redaction.sql)
  and [guarded rollback](../supabase/migrations/20260920030000_guarded_import_rollback.sql).
- **Administration and roles:** Admin is a task hub, and organisation role
  assignments have a working code path. Older README/gap-analysis statements
  describing both as absent are stale.
- **Redis, Flask and direct loading:** their absence is not a product gap.
  Durable Postgres jobs replace synchronous HTTP batches/cache-dependent work.
  Reviewed publication replaces direct writes to old table names and automatic
  ABN/name merges. Retain these current boundaries when adding sources.

The predecessors' lossy ACNC address mapping, name-only NSW merging, failure-to-empty
conversion and simulated slug-based loader should not be restored. Their concrete
defects and reuse boundaries are documented in the
[acquisition assessment](acquisition-code-assessment.md).

## Recommended sequence

1. **Finish already-planned qualification:** complete P16's live evidence and
   retention work, and observe the scheduled ACNC run when due. This preserves
   the order in [todo.txt](../todo.txt).
2. **Expand measured coverage:** qualify and implement the NSW register scraper
   (D01), then
   decide whether geographic ABN discovery (D02) provides enough additional
   coverage to justify integration. Reuse current staging and review.
3. **Make the larger dataset usable:** add directory search (U01), coverage
   reporting (D05/U06) and approved CSV export (D06). These can be delivered
   independently of full multi-provider orchestration.
4. **Integrate qualified ABN work:** connect exact lookups to jobs and review,
   then introduce reviewed ABN fact publication (D03). Add multi-provider
   orchestration and targeted acquisition controls when needed (D04/D08).
5. **Complete domain workflows:** prioritise correction forms, role-request UX
   and the legacy-model domains (U02–U05) according to actual user needs.

National ABN XML, AIS history, branch/service publication and further community
directory adapters remain expansion candidates already recognised in the
backlog. None should be counted as an implemented capability lost from these
two repositories. Importing their historical records is also separate from
feature parity; this review does not establish which records are already in
the live portal.

[etl]: https://github.com/BEN-DataDev/orgs-sveltekit-etl/tree/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9
[manager]: https://github.com/BEN-DataDev/orgs-data-manager/tree/dea271215b267097bc4364f562f62e784b2e1294
[api]: https://github.com/BEN-DataDev/orgs-sveltekit-etl/blob/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9/app/api/routes.py
[nsw]: https://github.com/BEN-DataDev/orgs-sveltekit-etl/blob/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9/app/extractors/nsw_assoc_extractor.py
[abn]: https://github.com/BEN-DataDev/orgs-sveltekit-etl/blob/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9/app/extractors/abn_extractor.py
[acnc]: https://github.com/BEN-DataDev/orgs-sveltekit-etl/blob/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9/app/extractors/acnc_extractor.py
[csv-writer]: https://github.com/BEN-DataDev/orgs-sveltekit-etl/blob/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9/app/utils/output.py
[manager-nsw]: https://github.com/BEN-DataDev/orgs-data-manager/blob/dea271215b267097bc4364f562f62e784b2e1294/web_worker/search_nsw_assoc_register.py
[manager-abn]: https://github.com/BEN-DataDev/orgs-data-manager/blob/dea271215b267097bc4364f562f62e784b2e1294/web_worker/search_abn_register.py
[manager-main]: https://github.com/BEN-DataDev/orgs-data-manager/blob/dea271215b267097bc4364f562f62e784b2e1294/main.py
[localities]: https://github.com/BEN-DataDev/orgs-data-manager/blob/dea271215b267097bc4364f562f62e784b2e1294/config_data/suburb_definitons.py
[csv-cleaner]: https://github.com/BEN-DataDev/orgs-data-manager/blob/dea271215b267097bc4364f562f62e784b2e1294/data/processing/clean_abn_csv.py
[csv-sql]: https://github.com/BEN-DataDev/orgs-data-manager/blob/dea271215b267097bc4364f562f62e784b2e1294/database/queries/copy_cleaned_abn_csv.sql
[models]: https://github.com/BEN-DataDev/orgs-data-manager/blob/dea271215b267097bc4364f562f62e784b2e1294/database/production/models.py
