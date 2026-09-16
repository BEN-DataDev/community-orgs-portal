# Acquisition code reuse assessment

Reviewed: 16 September 2026. Scope: code assessment and plan amendments; no production integration.

## Decision

Use **selected Python extractors from `orgs-sveltekit-etl` as the acquisition foundation**,
with `orgs-data-manager` as a source of regional configuration, alternative parser
behaviour and mapping references. Keep SvelteKit for operator UI and server-side
review. Replace direct loading and automatic merging with the portal's planned
private staging, evidence-based matching and approved publication workflow.

Despite its name, `orgs-sveltekit-etl` is a Flask/Python application, not a SvelteKit
frontend. Neither repository is a drop-in ingestion service for this portal.

## Reviewed versions

| Repository                                                                                                            | Pinned commit                              | Role                                                                                |
| --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ | ----------------------------------------------------------------------------------- |
| [orgs-data-manager](https://github.com/BEN-DataDev/orgs-data-manager/tree/dea271215b267097bc4364f562f62e784b2e1294)   | `dea271215b267097bc4364f562f62e784b2e1294` | Batch acquisition, regional configuration and prototype database mapping            |
| [orgs-sveltekit-etl](https://github.com/BEN-DataDev/orgs-sveltekit-etl/tree/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9) | `2676fdcc620e9a1c8beeacf587a8bcf688aa35c9` | Extractor classes, transformations, Flask orchestration, Redis and Supabase loading |

Cloned both repositories for inspection. Parsed all 19 and 17 Python files,
respectively, without syntax errors. Ran a synthetic fixture through the pure ETL
transformer and confirmed ACNC address-line loss. No test suite or licence file was
found in either checkout. A pytest dependency and example main blocks are not a
regression suite. Record code ownership/reuse rights and source attribution when
vendoring; repository visibility is not itself a reuse licence.

No complete application startup, dependency installation, authenticated registry
calls, Redis connection or database writes were performed. Current endpoint/schema
compatibility remains an implementation gate. This assessment does not establish
that all modules work against today's provider services.

## Module reuse matrix

Paths below are relative to the indicated repository. Links are pinned to the
reviewed code rather than a moving default branch.

| Module                                                                                                                                                                                                                                                                                                                                                      | Assessment                                                                                    | Integration action                                                                                                                                        |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ETL [`app/extractors/acnc_extractor.py`](https://github.com/BEN-DataDev/orgs-sveltekit-etl/blob/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9/app/extractors/acnc_extractor.py)                                                                                                                                                                                  | Useful CKAN filtering, pagination, ABN and name lookup                                        | Adapt; discover/configure active resources, validate schema and explicit completion. Retain bulk-download fallback.                                       |
| ETL [`app/extractors/abn_extractor.py`](https://github.com/BEN-DataDev/orgs-sveltekit-etl/blob/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9/app/extractors/abn_extractor.py)                                                                                                                                                                                    | Useful Zeep client, XML handling, exact ABN lookup and retry structure                        | Adapt client/parsing; inject credentials, bound SOAP calls and validate response versions. Charity search is not broad discovery of all community groups. |
| ETL [`app/extractors/nsw_assoc_extractor.py`](https://github.com/BEN-DataDev/orgs-sveltekit-etl/blob/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9/app/extractors/nsw_assoc_extractor.py)                                                                                                                                                                        | Useful ASP.NET form/session, result and detail parsers                                        | Adapt after source access/reuse qualification. Test current markup and all pagination termination cases.                                                  |
| Manager [`web_worker/search_nsw_assoc_register.py`](https://github.com/BEN-DataDev/orgs-data-manager/blob/dea271215b267097bc4364f562f62e784b2e1294/web_worker/search_nsw_assoc_register.py)                                                                                                                                                                 | Alternative NSW implementation checks top/bottom next links, disabled state and HTTP failures | Compare behaviours in shared fixtures; port useful checks into one maintained adapter.                                                                    |
| Manager [`config_data/suburb_definitons.py`](https://github.com/BEN-DataDev/orgs-data-manager/blob/dea271215b267097bc4364f562f62e784b2e1294/config_data/suburb_definitons.py)                                                                                                                                                                               | Useful locality/state/postcode seed                                                           | Convert to validated configuration and review pilot boundaries; do not equate postcodes with service coverage.                                            |
| Manager [`web_worker/search_anc_register.py`](https://github.com/BEN-DataDev/orgs-data-manager/blob/dea271215b267097bc4364f562f62e784b2e1294/web_worker/search_anc_register.py) and [`web_worker/search_abn_register.py`](https://github.com/BEN-DataDev/orgs-data-manager/blob/dea271215b267097bc4364f562f62e784b2e1294/web_worker/search_abn_register.py) | Earlier acquisition implementations                                                           | Use for comparison and fixtures; avoid maintaining duplicate clients.                                                                                     |
| ETL [`app/transformers/data_transformer.py`](https://github.com/BEN-DataDev/orgs-sveltekit-etl/blob/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9/app/transformers/data_transformer.py)                                                                                                                                                                          | Valuable field inventory but lossy mappings                                                   | Rework into tested, versioned normalisation; retain raw source values.                                                                                    |
| Manager [`database/production/mappings.py`](https://github.com/BEN-DataDev/orgs-data-manager/blob/dea271215b267097bc4364f562f62e784b2e1294/database/production/mappings.py)                                                                                                                                                                                 | Familiar portal domain names, but generic input assumptions                                   | Use as mapping reference, not executable migration authority. Reconcile with current UUIDs, JSON phone format and validation.                             |
| ETL [`app/api/routes.py`](https://github.com/BEN-DataDev/orgs-sveltekit-etl/blob/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9/app/api/routes.py)                                                                                                                                                                                                                | Useful source/postcode selection and run-summary ideas                                        | Reimplement as authorised queued jobs; replace automatic name merging and direct writes.                                                                  |
| ETL [`app/loaders/supabase_loader.py`](https://github.com/BEN-DataDev/orgs-sveltekit-etl/blob/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9/app/loaders/supabase_loader.py)                                                                                                                                                                                      | Writes flat records to `organizations`/`charity_details`                                      | Replace with private staging writer; current portal uses `community_orgs.organisations` and child tables.                                                 |
| ETL [`app/cache/redis_cache.py`](https://github.com/BEN-DataDev/orgs-sveltekit-etl/blob/2676fdcc620e9a1c8beeacf587a8bcf688aa35c9/app/cache/redis_cache.py)                                                                                                                                                                                                  | Optional JSON-cache helper                                                                    | Defer Redis; durable runs/checkpoints belong in Postgres. Do not make a cache a prerequisite for importing one file.                                      |
| Manager [`database/production/etl.py`](https://github.com/BEN-DataDev/orgs-data-manager/blob/dea271215b267097bc4364f562f62e784b2e1294/database/production/etl.py)                                                                                                                                                                                           | Simulated extraction and slug-based loading prototype                                         | Do not run against the portal; replace loading and identity logic.                                                                                        |

## Required fixes before reuse

1. **Lossy transformations.** The ACNC address dictionary repeats `street` four
   times; only the final `Address_Line_3` survives. The synthetic fixture lost valid
   lines 1 and 2 when line 3 was null. Preserve address type and each line separately.
   ABN output uses `entityDescription` and `acnc_status`, while the transformer reads
   `entityTypeDescription` and `anc_status`. Add contract tests across parser and
   transformer, and correct misspelled website/year keys at the boundary.
2. **Failure versus empty results.** ACNC pagination can stop after an exception
   and return accumulated records. Orchestration can convert extraction errors to
   `[]`. Replace list-only results with explicit `complete`, `partial` or `failed`
   outcomes. Only complete snapshots may drive missing-record reconciliation.
3. **Unsafe identity reduction.** Route-level merging indexes NSW records by uppercased
   name, permitting collisions, and collapses ABN-indexed records before branch
   scope is resolved. Preserve every source record; create candidate links instead.
4. **Request lifecycle and authorization.** Flask routes launch long synchronous
   postcode batches and write immediately. No route authentication checks were found
   in the inspected application. Do not expose those mutation routes unchanged.
   Move execution into jobs and enforce explicit platform-operator authorization.
5. **Startup coupling.** ABN configuration is required at module import; route imports
   instantiate Redis and Supabase helpers. Inject configuration per adapter/job so
   CSV and ACNC work without ABN credentials or Redis.
6. **Configuration and packaging.** The ETL deployment manifest supplies
   `SUPABASE_URL`/`SUPABASE_KEY`, whereas Config reads `PUBLIC_SUPABASE_URL` and
   `PUBLIC_SUPABASE_ANON_KEY`; active Redis construction uses host/port settings.
   The manager has machine-specific database/output settings and imports Zeep even
   though its requirements do not list it. Create a minimal reproducible worker
   environment; do not copy either requirements file wholesale.
7. **Provider compatibility.** Both ACNC implementations pin one resource ID.
   ABN parsing assumes the `SearchByABNv201408` response shape; NSW depends on HTML
   selectors and postback controls. Verify interfaces and fixtures before live use.
   Add finite connection/read/operation timeouts and retry budgets throughout.
8. **Coverage limitations.** ABN geographic discovery calls `SearchByCharity`;
   this cannot stand in for discovering every ABN-bearing club or informal group.
   Neither repo supplies the planned national bulk ABN parser, AIS financial-history
   pipeline, Landcare/peak-body adapters or My Community Directory integration.

These are source-level findings, not a claim that a live deployment is exploitable
or that provider services currently reject the legacy code.

## Integration boundary

Proposed local structure:

```text
tools/ingestion/python/
  pyproject.toml                  # selected and tested dependencies
  upstream-manifest.json          # repo, commit, source path, local path, changes
  ingestion/adapters/             # adapted Python acquisition clients
  ingestion/normalise/            # source-specific contract mappings
  ingestion/cli.py                # fixture and live jobs
  tests/fixtures/                 # permitted or synthetic responses
src/lib/server/ingestion/         # operator authorization and job/review actions
src/routes/admin/ingestion/       # SvelteKit operator interface
```

Start with a selectively vendored package here, pinned to the reviewed versions;
maintain one adapted implementation per provider. Consider a separate reusable
package later if both projects need ongoing shared maintenance. Do not merge entire
repositories or inherit their database schemas/deployment automatically.

The Python worker receives a validated job scope and emits versioned JSON/JSONL:
`source_id`, `native_id`, `run_id`, `observed_at`, `source_modified_at`, scope,
parser version, raw hash/reference, typed assertions, warnings and completion state.
ABNs/postcodes remain strings; nested source values remain objects, not JSON strings.
Validate this contract on both sides using shared fixtures. Source cursors/checkpoints
are persisted per job; publication is a distinct transaction, not an extractor step.

For the initial implementation, Python writes private staging through a restricted
database role or narrow ingestion RPC. SvelteKit reviews staged changes and invokes
the approved publication path. No public Python HTTP API is needed for the pilot.
Add durable jobs, leases and bounded worker concurrency before scheduling.

## Revised first work package

1. Record upstream provenance and code reuse rights; select the three extractor modules.
2. Extract dependency-injected acquisition/parsing code, avoiding Flask/Redis/loader startup.
3. Build synthetic and permitted response fixtures covering address lines, ABN field
   mappings, pagination, empty/partial/failure states and namespace variations.
4. Fix transformation contracts and establish the versioned staging envelope.
5. Demonstrate fixture → adapter → staging → dry-run report with no public writes.
6. Validate a bounded current ACNC resource, then exact ABN lookup when configured.
   Keep the NSW adapter disabled until access/reuse and live parsing are qualified.

Reuse should reduce source-discovery and parser implementation work. It does not
remove the need for provenance, authorization, matching review, suppression,
publication or operations. Retain the existing pilot estimate until this work package
has measured how much of each client survives qualification.
