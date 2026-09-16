# ACNC acquisition tools

Requires Python 3.10 or later. Uses only the standard library; no installation,
credentials, database, Flask, Redis or network connection is needed.

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
become false or deletion assertions. Source dates remain labelled raw strings until
a verified source-specific date mapping exists.

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
`config/acnc-pilot.json`, disabled by default. The supplied pilot uses postcode
2730, five records per page and at most two pages (ten fetched records).

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
- One exact four-digit postcode, explicit resource UUID, licence-title agreement and
  active resource membership in the `acnc-register` package required.
- Source schema checked on every page; records outside the postcode rejected.
- Page size/page count caps, hard ceiling of 500 records per configured run.
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
