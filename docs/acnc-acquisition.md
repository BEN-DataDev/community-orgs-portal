# ACNC acquisition (P13)

Complete locally, 18 September 2026, with live read-only acquisition verification.
The existing deployed CKAN worker remains in place. This increment adds the bulk
CSV fallback, checks every mapped live schema field, and writes acquisition
manifests. It does not deploy a worker, enable a source, schedule a job or publish.

## Acceptance

| Requirement                                 | Implementation and evidence                                                                                                                                                                                                                                             |
| ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Adapt the existing extractor                | [Pinned upstream provenance](../tools/ingestion/python/upstream-manifest.json); injected transport and standard-library Python, no legacy application/loader dependencies.                                                                                              |
| Qualify the configured resource and schema  | Package membership, reviewed licence, metadata before/after acquisition; exact 70-field CKAN schema or 69-column CSV header. Missing/extra/duplicate/type-changed fields fail closed, including empty CKAN results.                                                     |
| Emit versioned staging records and manifest | Contract `1.0`; `acnc-ckan-v3` or `acnc-bulk-v1`; mapping `acnc-register-fields-v3`. Private `envelope.json` and `manifest.json` bind source/resource, scope, observation, parser/mapping, limits, completion and canonical envelope hash.                              |
| Bulk-resource fallback                      | [Bulk CLI](../tools/ingestion/python/ingestion/bulk_acnc.py) downloads the pinned CSV resource directly, independently of DataStore availability, then scans it to EOF and retains the bounded postcode cohort. Live six-record typed assertions matched the CKAN path. |
| Safe staging/replay                         | [Database regression](../supabase/tests/acnc_bulk.sql) stages real parser output as the restricted worker, reuses the same run/version on replay and creates no organisation, link or publication.                                                                      |

The fallback is an explicit operator command, not an automatic retry from the
scheduled worker. A CKAN failure remains a failed/partial acquisition; it is never
relabelled as a successful bulk acquisition. Each path has its own run and evidence.

## Qualified resource and limits

The public [ACNC CSV resource](https://data.gov.au/data/dataset/acnc-register/resource/8fb32972-24e9-4c95-885e-7140be51be8a)
is a separate resource from the existing XLSX-backed DataStore resource
`eb1e6be4-5b13-4feb-b28e-388bf7c26f93`. Direct package metadata inspection confirmed
CSV resource `8fb32972-24e9-4c95-885e-7140be51be8a`, the configured download URL and
Creative Commons Attribution 3.0 Australia. The runtime rechecks these facts on
each run. This is the Register, not AIS financial history.

The [disabled example configuration](../tools/ingestion/python/config/acnc-bulk-pilot.json)
pins that CSV, the [23-postcode Snowy Valleys scope](snowy-valleys-postcode-scope.md),
a 64 MiB download cap, 100,000 scanned rows, 90-second overall deadline and
10-second per-request timeout. `page_size * max_pages` is the selected-record cap
(1,000 in this configuration); in bulk mode those settings do not cause
pagination. Configuration rejects larger global caps.

Only a pinned HTTPS `data.gov.au` resource-download path is allowed. Redirects,
unexpected compression, oversized responses and advertised-length mismatches fail.
Metadata requests retain bounded retries/backoff; a partial CSV download is not
retried within the same run. Start a new run after diagnosing failure. The CSV is
streamed through a private temporary file and removed on completion; only selected
raw rows, quarantine evidence, file hash/size and scan diagnostics are retained.
The CLI outputs use mode 0600 in a new mode-0700 directory and refuse overwrite.
Normal shutdown removes the temporary full file; no national register is committed.

The UTF-8/optional-BOM CSV parser handles quoting, embedded newlines and Unicode.
It requires exactly the reviewed headers, consistent column counts and no NULs.
The standard-library CSV field-size limit also bounds individual fields; oversized
fields fail rather than truncate. Extra/missing columns require mapping review.

Postcode selection compares the trimmed source text to the configured list of
four-digit postcodes, preserving leading zeros. Rows outside that scope are not
portal records.
Missing/invalid identities outside the scope are counted as diagnostics. In-scope
missing/invalid identities are quarantined, and duplicate identities touching the
selected cohort make the run partial, even if the other occurrence is outside it.
All rows are scanned to catch those conflicts. Completion means EOF was reached
without selected quarantine or structural/acquisition errors; it does not assert
national coverage or justify deletion reconciliation. An empty scoped result is
complete only after a successful full scan and stable metadata checks.

Metadata comparison and transport checks cannot guarantee an atomic source
snapshot or detect every upstream truncation; `snapshot_guaranteed` remains false.
HTTP EOF without a published row count is not proof of a complete national register.

## Identity and publication boundary

The observed CSV has no CKAN `_id`. Its qualified native key is `abn:<source ABN>`,
scoped to the CSV resource. The parser does not fabricate `_id`, use row numbers as
identity or pretend that CSV keys are existing XLSX/DataStore keys. Raw ABNs remain
strings and are not registry-verified by this choice. Duplicate keys are errors,
not instructions to merge. If a separately qualified CSV actually supplies `_id`,
an explicit `_id` identity mode is available with that additional required header;
that mode was fixture-tested, not observed on this live CSV.

This follows the [P11 identity contract](identifier-entity-mapping.md). A reviewer
must link bulk candidates to existing organisations using evidence; do not approve
new organisations merely because the bulk source has no existing source links.
P14 deterministic matching and P16 exact-ABN verification remain separate work.

The existing private `stage_acnc` RPC accepts the envelope without a migration.
The CSV resource must first be separately registered, qualified and enabled in the
private source registry; enabling the XLSX resource does not enable the CSV.
This P13 check did not perform that onboarding or stage real data.

All 62 review units are emitted as assertions. Current publication supports the
three baseline fields (name, ABN, website) for this new parser; its other fields
remain unmapped by the database's parser allowlist. Enabling full-field bulk
publication requires a reviewed allowlist/migration and publication tests. The
existing retained-CKAN replay tool also assumes `_id` and must not be used to
reprocess this ABN-keyed CSV. Neither limitation prevents private P13 acquisition
and staging. `publication_eligible=false` never grants publication authority.

## Commands

From `tools/ingestion/python`, after reviewing the selected configuration:

```sh
# Existing bounded DataStore acquisition; now also writes manifest.json.
python3 -m ingestion.live_acnc --config config/acnc-pilot.json \
  --enable --output-dir /private/new-acnc-pages-run

# Explicit direct CSV fallback; no DataStore request or database connection.
python3 -m ingestion.bulk_acnc --config config/acnc-bulk-pilot.json \
  --enable --output-dir /private/new-acnc-bulk-run

# Optional SQL artifact only, after inspecting completion and qualification.
python3 -m ingestion.staging_sql --input /private/new-acnc-bulk-run/envelope.json \
  --output /private/new-acnc-bulk-run/stage.sql
```

Choose a new private directory per acquisition. Keep generated SQL private too;
it contains encoded raw evidence. `--enable` enables only this CLI invocation,
not database source registration or publication. Exit 0 means complete acquisition;
partial/failed runs write diagnostic artifacts and exit 1. Invalid configuration
or an existing output directory fails before acquisition. The manifest's envelope
hash uses canonical JSON (`digest`), not the pretty-printed file bytes; the bulk
file hash is SHA-256 of the actual downloaded bytes.

## Verification — 18 September 2026

Live acquisitions retained only private temporary pilot envelopes/manifests. A
contact-free [validation summary](acnc-p13-validation.json) records their hashes,
resource metadata and counts. The first bulk attempt stopped at row 104 because
the initial implementation rejected every missing ABN. Aggregate inspection found
605 blank ABNs outside the selected postcode. The corrected scoped behavior above
has a regression test; selected missing identities still quarantine.

The successful bulk run scanned **66,315 rows**, **15,093,328 bytes**, reached EOF,
and selected **six records with no quarantine**. The direct CKAN run completed
with six records across two pages and the full 70-field schema. Comparing typed
assertions by ABN found identical facts for all six records; this comparison is
validation, not persisted cross-resource matching or ABN verification.

Local checks:

- 74 Python tests and full mapping coverage passed, including limits, malformed
  CSV/encoding, schema drift, identity conflicts, partial outcomes and private outputs.
- 36 unmodified migrations, 16 SQL suites, approved-CSV integration and concurrent
  owner-revocation checks passed in disposable PostGIS 17, including P13 staging.
- The real worker recovery harness passed both interruption points, checkpoint
  reuse, protected edits, withdrawal replay and failed/partial source scenarios.
  It used an isolated Docker network and synthetic source responses.

Reproduce with `python3 -m unittest discover -s tests` and
`python3 -m ingestion.field_coverage` from the Python directory, and
`python3 scripts/test-operator-access-db.py` plus
`python3 scripts/test-acquisition-recovery.py` from the repository root.

No application UI changed, so a Svelte build is not needed. No hosted migration,
source enablement, staging, publication, deployment or schedule change was made.
To deploy the stricter CKAN checks, rebuild/restart the worker using its existing
[deployment procedure](acquisition-jobs.md); new jobs use the new checks while
existing immutable checkpoints remain resumable. Scheduling, national snapshot
reconciliation and full-field bulk publication are separate release decisions.
