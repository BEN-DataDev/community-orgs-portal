# Offline ACNC acquisition prototype

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
There is no live transport and no publication or database writer.

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
