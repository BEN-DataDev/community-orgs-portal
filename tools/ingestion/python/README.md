# ACNC acquisition tools

Requires Python 3.10 or later. Uses only the standard library; no installation,
credentials, database, Flask, Redis or network connection is needed for offline
fixtures. Live acquisition requires network access; staging is a separate operation.

P33 adds the offline `ingestion.abr_bulk` adapter for separately downloaded national
ABN bulk releases. It streams every XML member across the inventoried ZIP parts,
checkpoints completed parts, retains only configured-postcode and known-ABN candidates,
and emits the private P31 registry-seed contract. See the
[P33 operation guide](../../../docs/abn-bulk-seed.md). It does not download, stage,
triage or publish data by itself. The first qualified release is assigned to the
local operator workstation using an approved absolute path outside Git; Vercel is
not the P33 runner or artifact store.

P13 adds an explicit bounded bulk CSV fallback and acquisition manifests. Both
paths were verified live against the six-record postcode 2730 cohort. See the
[P13 operation and validation guide](../../../docs/acnc-acquisition.md) for commands,
resource identity, limits and the separate bulk publication boundary. The example
configurations remain disabled; the deployed scheduled worker is not switched to
bulk acquisition.

F05 now provides `python3 -m ingestion.reprocess_acnc` for offline replay of a
complete retained acquisition using the new parser/mapping. It preserves original
observation/evidence and emits a separate private run; it never approves or
publishes. F02–F05 migrations are applied live. The partial v2 replay remains run 7;
the complete six-record v3 replay is now staged as run 8. See the [F05 report and commands](../../../docs/acnc-reprocessing-validation.md).

Current local code uses parser/mapping v3 and `mappings/acnc-register-v3.json`.
Bare ASCII DNS websites receive an explicitly recorded HTTPS default; ambiguous
formats still quarantine. The v3 migration is applied live, with fresh review and
separate publication still required. See [qualification and tests](../../../docs/acnc-website-normalisation.md).

From this directory:

```bash
python3 -m unittest discover -s tests -v
python3 -m ingestion.cli --fixture tests/fixtures/acnc-pages.json --output examples/acnc-normalised.json
```

The CLI accepts explicitly synthetic fixtures only. Exit status is 0 for complete
extraction and 1 for partial/failed extraction. It writes the diagnostic envelope
in all three cases. File/configuration errors may instead raise a Python error.
This offline command has no live transport. The separate live client is described below; neither client publishes data or connects to a database.

The separate `ingestion.staging_sql` command now validates an envelope and emits
SQL for private staging (it opens no database connection). See
[private staging](../../../docs/private-staging.md) for migration and test results.

## Adaptation

`ingestion/adapters/acnc.py` adapts the upstream CKAN filter/offset algorithm into
a dependency-injected client. `upstream-manifest.json` records the reviewed source
commit, source-file hashes, use and modifications. The upstream code licence was
not established; local adaptation follows the user's explicit request, and external
redistribution needs ownership/licensing confirmation.

One exact query scope is processed per run. The caller supplies an explicit
resource ID and a `fetch_page(params) -> CKAN response dict` function. No legacy
resource ID is assumed valid. Pagination requests sort by `_id`, checks totals,
rejects repeated source IDs, and stops at a configured page budget.

The normaliser preserves all address lines and address type. Missing ABNs are
retained for review; matching/deduplication by ABN is deliberately not performed.
Nested addresses are objects, identifiers are strings, and omitted values do not
become false or deletion assertions. The current mapping preserves raw source dates
alongside typed assertions using the qualified source-specific date rules.

## P04 source qualification

See the [source qualification record](../../../docs/source-sample-qualification.md)
for retained ACNC evidence, the versioned synthetic CSV fixture under
`tests/fixtures/csv-pilot-v1`, and ABN access preparation. The CSV schema and manifest
are a synthetic P12 contract exercised by the implemented importer, not an approved real export.
Do not pass these CSV records to the ACNC-specific staging commands.

## Fixture and output

`tests/fixtures/acnc-pages.json` contains two invented records, not copied register
data. The all-zero ABN is intentionally an **unverified synthetic placeholder**;
only format is checked. No assertion of checksum validity or actual registration
is made. The no-ABN example tests defensive handling, not actual ACNC coverage.

`examples/acnc-normalised.json` is reproducible output. The fixed observation time
is fixture metadata, not evidence of a live registry check.

Envelope contract v1.0:

- Source/resource/run IDs, explicit query scope, observation time and parser version.
- `completion`: `complete`, `partial`, or `failed`; counts, page hashes and errors.
- Accepted records: resource-scoped native ID, source URL, raw data/hash, assertions,
  warnings and timestamps. Unknown source modification time is null.
- Quarantine: source row index, rejected raw value and reason.
- `publication_eligible: false`, even for complete runs; acquisition is not approval.
- `synthetic: true` is added by this offline CLI.

Here, `complete` means the fixture pages passed the count/schema checks for the
requested scope. It does not prove a live source is a consistent snapshot or that
all Australian charities were obtained. A changed resource may reassign CKAN `_id`
values; qualify stable identity before linking records across resource revisions.

## Next implementation boundary

See [schema review](../../../docs/acnc-prototype-schema-review.md). A six-record
current source sample and private staging migration have now been validated; see
[staging implementation](../../../docs/private-staging.md). SvelteKit integration
and consumer-side validation remain pending. A future live transport needs finite HTTP timeouts,
bounded retries and response-size limits. No such transport is enabled here.

## Bounded live acquisition

The standard-library `ingestion.live_acnc` client qualifies the configured CKAN
resource and produces the same private staging envelope. Configuration is in
`config/acnc-pilot.json`, disabled by default. The supplied pilot uses the 23-code
Snowy Valleys discovery cohort, 100 records per page and at most ten pages (1,000
fetched records).

```bash
python3 -m ingestion.live_acnc --config config/acnc-pilot.json --enable --output-dir /tmp/acnc-pilot-new-run
python3 -m ingestion.staging_sql --input /tmp/acnc-pilot-new-run/envelope.json --output /tmp/acnc-pilot-stage.sql
chmod 600 /tmp/acnc-pilot-stage.sql
```

`--enable` enables this acquisition invocation only. It does not enable publication
or change the database source registry. The output directory must be new; the
client writes it with mode 0700 and the envelope with mode 0600. Store outputs
outside the repository. Exit code 0 means a complete scoped extraction; partial
or failed acquisition writes its evidence envelope and exits 1. Configuration
errors fail before acquisition. Do not treat an incomplete run as disappearance
of records or a complete register snapshot.

Controls:

- HTTPS endpoint fixed to data.gov.au, two allowlisted CKAN actions, redirects refused.
- Between 1 and 50 sorted, unique four-digit postcodes, an explicit resource UUID,
  licence-title agreement and active resource membership in the `acnc-register`
  package are required.
- Source schema checked on every page; records outside the postcode cohort rejected.
- Page size/page count caps, hard ceiling of 1,000 records per configured run.
- Byte cap per HTTP response, socket timeouts and a shared request/time budget.
  Deadline checks occur between reads; an in-flight read can last one socket timeout.
- Three attempts maximum per request, bounded exponential backoff for network errors,
  HTTP 429/500/502/503/504, and respect for Retry-After within the remaining budget.
  Other HTTP errors, schema changes and invalid JSON fail immediately.
- Metadata hash rechecked after pagination; drift or a failed recheck prevents
  completion. This is evidence of stability, not an atomic CKAN snapshot guarantee.

The envelope includes metadata qualification, resource modification time, licence,
schema, page hashes, configured limits and request count. Source dates remain raw
assertions; matching/publication and deletion reconciliation are separate.

The live qualification report in `docs/acnc-live-pilot-validation.json` records the
first six-row pilot without retaining raw contacts in the repository. Records are
staged privately in Supabase run 6. The real ACNC source is paused (`enabled=false`)
after staging, so approval/publication remain blocked pending source/mapping review.
Source enablement and credentials remain database-administrator operations; this
increment does not provide a source-management UI, scheduler or worker login.

## ACNC field inventory (F01)

From `tools/ingestion/python`:

```sh
python3 -m ingestion.field_coverage
python3 -m ingestion.field_coverage --write
python3 -m unittest discover -s tests
```

The active versioned contract is `ingestion/mappings/acnc-register-v3.json`;
`acnc-register-v1.json` retains the historical v2 contract. The generated
report is `docs/acnc-field-coverage.md` at the repository root. `--write` regenerates
only the report. To check a newly observed schema, use `--schema /path/schema.json`
with a JSON object of column names to CKAN types. Unknown, missing or changed fields
fail the check. This offline coverage check does not enable publication. F02
uses the contract in runtime normalisation; unknown row keys require review. The complete synthetic fixture and edge
cases are in `tests/fixtures/acnc-field-coverage.json`.

## F02 schema and transformations

F02 introduced `acnc-ckan-v2` / `acnc-register-fields-v2`; current local acquisitions
use v3 with the qualified website rule described above. All mapped
organisation columns become typed assertions, with source spellings/raw values
and mapping version retained in the private version payload. Invalid values or
unknown columns quarantine the whole record. Blank/missing values create no
assertion and cannot clear published data. Dates accept only DD/MM/YYYY,
calendars DD-Mon (English), flags Y/N; other tokens require qualification.
Names and country lists remain unsplit text. Address lines retain their positions.

Apply `20260916070000_acnc_register_details.sql` through the normal migration
process. It adds default-private storage with validated JSON groups and no browser
writes. Public column grants exclude source-record IDs. F03 implements
per-fact provenance, approval and suppression for these projections.
No existing pilot version or approval is rewritten. Run transformation tests with
`python3 -m unittest discover -s tests`; database checks are in
`supabase/tests/acnc_register_details.sql`.

## F03 review and publication

`20260916080000_complete_field_publication.sql` adds a private, closed allowlist
that is checked against the mapping manifest by the Python suite. It supports 62
review units for 69 organisation columns: address components form one atomic
merge; each flag is independent. Preview shows missing, invalid, unmapped,
protected and suppressed facts explicitly. Source omissions never delete values.
Approval snapshots include source values, parser/mapping state, source identity
and target revisions. Pending approvals made before F03 require renewed review;
already completed publications remain idempotent. Updating a mapping or validator
requires a new mapping/snapshot version and fresh approval.

The new table preserves distinct source projections and source-scoped revisions.
Ordinary writes protect edited facts; only the private publication RPC can clear
protection on its selected writes. Hidden existing projections stay protected.
Suppression clears a selected fact from all source projections of the target and
blocks direct or imported restoration. Whole-record/name withdrawal hides the
organisation. No field grants ownership or verification status.

Local verification from the repository root:

```sh
python3 scripts/build-ingestion-test-sql.py > /tmp/ingestion-test.sql
# Apply that file with psql -v ON_ERROR_STOP=1 ONLY to an empty disposable database.
node scripts/test-ingestion-review.mjs
# Requires Playwright and an installed browser; PLAYWRIGHT_MODULE can specify its module path.
node scripts/test-ingestion-field-groups.mjs
npm run check
```

The generated SQL uses real organisation/contact/legal definitions and ingestion
migrations, plus emulated auth helpers. It exercises rollback, replay, stale
approvals, per-field suppression, source scoping, manual protection and access.
It must never run against a deployed database. F04 implements public rendering;
reprocessing the retained pilot with new approvals remains F05.

## F04 public presentation

`20260916090000_public_register_facts.sql` adds a public-only RPC for latest
approved observations per source identity/field. It returns a closed set of public
fields and attribution metadata. It excludes raw envelopes, internal IDs, reviewer
notes, unpublished approvals, hidden projections and suppression/withdrawal data.
Existing organisation pages render all review units in their domain sections;
responsible-person counts appear as a Governance summary on Overview. The display
labels source observations explicitly and retains source disagreements.

The database test builder also runs `public_register_facts.sql`. Its single
`f04_browser_fixture` JSON result contains public/suppressed/withdrawn scenarios
captured under `SET ROLE anon`. Save that JSON as `/tmp/f04-browser.json`, then run:

```sh
node scripts/test-public-register-pages.mjs
# Set PLAYWRIGHT_MODULE to an installed Playwright module path to also run browser checks.
```

`REGISTER_PAGE_FIXTURE` can override the fixture file path. The test runs the real
page loaders and Svelte server rendering against exported anonymous results,
checking all 62 review units across five pages and withdrawn-page 404s. It uses
no hosted credentials. The SQL harness emulates auth helpers; hosted application
verification and retained-pilot replay remain F05 work.

## Queued acquisition worker

Run `python3 -m ingestion.worker` from this directory with a dedicated libpq
connection configured for a LOGIN belonging to `ingestion_worker`. It processes
one queued job and exits; invoke periodically from a supervisor. Requires `psql`
on PATH and Python 3.10+, with no additional Python packages. Never use a portal
administrator database login for the deployed worker.

The operator UI queues work; the cron route enqueues due configurations; only the
worker fetches CKAN. The worker saves a private envelope checkpoint, then commits
staging and job completion together. No publication is performed. Schedules start
off and require platform-admin configuration. See [deployment, recovery and
validation](../../../docs/acquisition-jobs.md) and the optional service/timer files
in `../deploy`.

## Approved CSV files (P12)

`python3 -m ingestion.approved_csv --input organisations.csv --manifest manifest.json
--output envelope.json --sql-output stage.sql` validates an approved export and emits
private staging evidence. See [the CSV operation guide](../../../docs/approved-csv-import.md)
for the qualified manifest, exit codes, staging migration and review workflow.

## Exact-ABN acquisition (P16)

`python3 -m ingestion.exact_abn` supplies bounded private registry evidence.
See [the runbook](../../../docs/exact-abn-lookup.md) for credentials, limits,
operator review, retention and pending live qualification.
