# Complete public register field coverage

Priority: next implementation work, before acquisition jobs or scheduling.
Prepared 16 September 2026. This is a plan, not completed field support.

## Outcome and scope

Every organisation fact supplied by an approved public register must have a public
presentation and a traceable source, or an explicit documented exclusion. Cover
all fields in each acquired resource, not just those populated in the six-record
pilot. This does not promise fields the resource does not supply. Raw acquisition
metadata, credentials, reviewer notes and internal IDs are not organisation facts.
Publication still requires review; source enablement is not permission to publish
raw envelopes. Withheld, withdrawn or suppressed values must remain unavailable.

Current publication supports only name, ABN and website. Address, dates and other
names are extracted but unmapped; remaining ACNC facts are retained in private raw
records. Existing page/table support does not imply working import support.

## Code to use as the basis

Reviewed local snapshots match the commits in [the earlier assessment](acquisition-code-assessment.md).
These findings are source inspection, not new live ABR/NSW compatibility tests.

| Existing code                                                                                                                                                                                                                                                                                         | Reuse in this work                                                                                                                                                                     | Required changes                                                                                                                                                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| ETL [data_transformer.py](https://github.com/BEN-DataDev/orgs-sveltekit-etl/blob/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9/app/transformers/data_transformer.py)                                                                                                                                       | Starting inventories for ACNC identity, address, dates, size, responsible-person count, jurisdictions, purposes and beneficiaries; ABR status and endorsements; NSW registration facts | Replace repeated `street` keys; correct `charity_wbsite`, `finacial_year_end`, mismatched ABR keys, outdated ACNC field names/case and `Operates_in_Countries` versus observed `Operating_Countries`. Separate purposes, beneficiaries and PBI/HPC classification. |
| Manager [mappings.py](https://github.com/BEN-DataDev/orgs-data-manager/blob/dea271215b267097bc4364f562f62e784b2e1294/database/production/mappings.py)                                                                                                                                                 | Declarative source-to-domain mapping approach and candidate organisation, alias, contact, legal and endorsement destinations                                                           | Reconcile with actual portal types and constraints. Replace Python `bool(string)` conversions, silent truncation and generic input names. Source strings must not set visibility or actor IDs.                                                                     |
| ETL [abn_extractor.py](https://github.com/BEN-DataDev/orgs-sveltekit-etl/blob/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9/app/extractors/abn_extractor.py)                                                                                                                                               | XML extraction and exact-ABN lookup as the later ABR adapter basis                                                                                                                     | Contract tests for `entityDescription` and `acnc_status`; keep nested names, GST, DGR and concessions as typed arrays/objects rather than JSON strings. Preserve effective dates and multiple occurrences.                                                         |
| Manager [clean_abn_csv.py](https://github.com/BEN-DataDev/orgs-data-manager/blob/dea271215b267097bc4364f562f62e784b2e1294/data/processing/clean_abn_csv.py)                                                                                                                                           | Column inventory, expected-column checks, sentinel-date handling and duplicate diagnostics                                                                                             | Parameterise paths; read identifiers as strings before inference; parse nested values; retain duplicates for identity review. Validate sentinel interpretation against source semantics.                                                                           |
| ETL [nsw_assoc_extractor.py](https://github.com/BEN-DataDev/orgs-sveltekit-etl/blob/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9/app/extractors/nsw_assoc_extractor.py)                                                                                                                                   | Registration number, type, status, registration/removal dates and registered-office parser                                                                                             | Qualify current source/access and parser fixtures before enabling; preserve jurisdiction and full status values.                                                                                                                                                   |
| Manager [etl.py](https://github.com/BEN-DataDev/orgs-data-manager/blob/dea271215b267097bc4364f562f62e784b2e1294/database/production/etl.py), ETL [supabase_loader.py](https://github.com/BEN-DataDev/orgs-sveltekit-etl/blob/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9/app/loaders/supabase_loader.py) | Reference for pipeline boundaries only                                                                                                                                                 | Keep the portal's staging/review/publication path. Do not reuse slug matching, simulated extraction, direct writes or legacy destination schemas.                                                                                                                  |

Record each adapted module, upstream commit and correction in the upstream
manifest. Extend the existing Python package; do not introduce a second ETL server.

## Ordered implementation packages

### F01 — Machine-readable field inventory and mapping contract

Start with the observed ACNC schema in `acnc-live-pilot-validation.json`, compare
it with both repositories and retained raw records, and account for every column.
Deliver a versioned mapping manifest and a generated human-readable coverage table.
Each entry needs source key/type, meaning, canonical key/type, transformation,
null/unknown handling, cardinality, proposed table/column, public page/label,
review unit, attribution and suppression rules, fixture and implementation status.
Technical columns such as `_id` get an explicit non-public classification.

Do not infer missing categories from the small pilot. Add synthetic fixtures for
all known columns. Unknown future columns must produce a coverage warning and
require mapping review; never silently claim complete coverage.

### F02 — Schema and transformations

Use current portal destinations when semantically correct; add migrations for
facts or cardinalities they cannot represent. Choose exact tables during F01.

| ACNC information                                                       | Planned public destination and semantics                                                                                   |
| ---------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Legal/other names, establishment date                                  | Overview and aliases; preserve unclassified other-name text until splitting/type rules are qualified                       |
| ABN, registration date, PBI/HPC, charity size                          | Legal/registration section; distinct dated source facts, not invented verification or boolean status inferred from absence |
| Address type, all three address lines, locality/state/postcode/country | Contact section with structured administrative address and source role; not automatically a service or street location     |
| Website                                                                | Contact section; retain original evidence and validate the public URL                                                      |
| Financial year end                                                     | Finance section as a reporting calendar value, not a fabricated dated financial result                                     |
| Responsible-person count                                               | Governance summary; distinguish count from named people                                                                    |
| Operating states/territories and countries                             | Operations section, preserving source meaning without inferring service availability everywhere                            |
| Charitable purposes and beneficiary flags                              | Labelled public groups with explicit true/false/unknown semantics; separate classification vocabularies                    |

Use the complete manifest for exact column coverage; this table groups work and
is not itself the exhaustive inventory. Preserve source spellings in provenance
while using corrected canonical names. Parse dates using declared source formats,
keep postcodes/ABNs as strings, distinguish blank from false, and quarantine invalid
values rather than silently replacing them with null. Preserve source values when
normalisation is ambiguous. Keep reporting dates separate from import timestamps.

Later source packages apply the same contract to ABR entity/status history,
names, GST/DGR/concessions and locality; NSW incorporation facts; then other
qualified sources. AIS reporting-period financial observations require a separate
adapter and schema package: neither inspected repository supplies that pipeline.

### F03 — Review and publication for every supported field

Extend preview, approval snapshots, validation, transaction writes, manual-edit
protection, attribution and suppression together. Remove the current three-field
limit only with the corresponding allowlisted mappings. For child lists, approve
stable items or explicit atomic groups with their full diff; never hide list
replacement behind a scalar checkbox. Keep removed/missing source values from
implicitly clearing published data. Stale approvals must fail after mapping,
source version or target changes. No automatic identity merging on ABN/name/slug.

Group review fields by Overview, Legal, Contact, Operations, Finance and Governance.
Provide select-all-eligible within a group and clear excluded/conflicting/invalid
counts. Show which supplied facts are still unmapped. Saving approval continues to
be distinct from publication.

### F04 — Public rendering and access

Render approved facts on the existing organisation sections with source links and
observation/effective dates. Add a clearly labelled register-details section if a
source-specific fact has no natural domain location. Source disagreements remain
attributed rather than silently choosing a winner. Do not expose private raw JSON
as a shortcut. Check anonymous reads through both pages and database policies;
manual administrator inspection alone is not public-access verification.

### F05 — Reprocess the pilot and verify completeness

Re-normalise retained raw records using a new parser/mapping version and a new,
explicit reprocessing run linked to the original acquisition. Preserve its
observation time and original evidence hashes; do not pretend this is a fresh
registry observation. Do not mutate run 6 or its approved source versions. Carry
existing identity links forward only after validating source identity; show
previously published values and protected conflicts in the new review.

Test ABN 75349327058 and all six pilot records, supplemented by synthetic records
for fields absent in the pilot. Existing approvals must not authorise newly added
facts. Withdrawals must survive reprocessing and prevent restoration.

Release gate:

- Every observed source column has a manifest entry; every public organisation
  fact has a working destination or a documented exclusion (no unexplained gaps).
- Parser-to-transformer fixtures catch upstream address/key/boolean defects.
- Publication round trips every supported scalar and repeated structure without
  truncation; permissions, stale approvals and protected edits are exercised.
- Anonymous pages show approved facts and attribution; private evidence and
  withdrawn facts remain inaccessible, including after replay.
- Replaying a version creates no duplicate organisations or child records.
- A coverage report distinguishes supplied, absent, invalid, unmapped, approved,
  published and suppressed fields. Missing source information is not called an
  implementation success or invented to fill a page.

Only after F01–F05 pass should acquisition job controls and scheduling resume.
Broader sources follow their own qualification and complete-field coverage gates.
