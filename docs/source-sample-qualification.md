# P04 source sample qualification

Completed: 17 September 2026. Scope: qualify the retained ACNC sample and a
synthetic CSV fixture, and prepare ABN access. P12 remains responsible for the
CSV importer; P16 remains responsible for exact-ABN integration and live checks.

| Source                 | Qualification evidence                                                                                           | Decision                                                                                    |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| ACNC Register          | Six-record postcode 2730 observation; exact resource, revision dates, hashes, licence and 70-column schema below | Qualified for the recorded bounded sample; later acquisitions recheck metadata/schema       |
| Project CSV fixture v1 | Nine invented records, file hashes, explicit use basis, attribution, schema and expected review outcomes         | Qualified for offline development only; no real provider export or publication approval     |
| ABN Lookup             | Official registration, agreement and method documentation checked 17 September 2026                              | Access preparation complete; registration/GUID and live adapter verification remain pending |

P04 does not qualify a real NSW associations export, complete P12/P16, or enable
another source. A synthetic CSV establishes a development contract, not evidence
of a provider's actual format or permission. No source configuration, hosted data,
schedule or publication was changed.

## ACNC retained sample

Publisher: Australian Charities and Not-for-profits Commission (ACNC).
Access: public CKAN DataStore JSON, without credentials; the catalogue resource
is labelled XLSX. Dataset `acnc-register`, ID
`b050b242-4487-4306-abf5-07ca073e5594`; resource **ACNC Register of Australian
charities**, ID `eb1e6be4-5b13-4feb-b28e-388bf7c26f93`.

- [Dataset metadata endpoint](https://data.gov.au/data/api/3/action/package_show?id=acnc-register).
- [Exact resource](https://data.gov.au/data/en/dataset/acnc-register/resource/eb1e6be4-5b13-4feb-b28e-388bf7c26f93).
- [Retained observation and qualification](acnc-live-pilot-validation.json):
  observed `2026-09-16T04:47:41.708096+00:00`, acquisition ID
  `acnc-b56fd67b-3b7d-49b5-bbd9-41da48252cf8`.
- Resource modified `2026-09-13T19:00:59.574359`; package metadata modified
  `2026-09-13T19:56:51.506354` (source timestamps retained as supplied).
  Metadata SHA-256:
  `554e8d7c27a12edeb2e8014023167f4b3d6ee90cc9095f07a433f32b593968f0`.
- Exact filter: `Postcode = "2730"`; page offsets 0 and 5, page sizes 5 and 1.
  Six accepted records, zero quarantine; page hashes are in the retained report.
  Completion applies only to this filtered observation, not a national/atomic snapshot.

The retained resource metadata declares **Creative Commons Attribution 3.0
Australia**, with licence URL <http://creativecommons.org/licenses/by/3.0/au/>.
Use that resource declaration, not a generic website footer. The attribution
specification for this sample is: “Source: Australian Charities and Not-for-profits
Commission, ACNC Register of Australian charities. Licensed under Creative Commons
Attribution 3.0 Australia. Adapted by Community Organisations Portal.” Link the
resource and licence, and display the applicable observation/publication dates.
This specifies the source contract; it does not claim this exact wording was
reconfigured in production during P04.

This qualification relies on the recorded September 16 metadata. Browser retrieval
of the catalogue on September 17 returned 403 and the metadata endpoint could not
be retrieved through that browser tool; no new live ACNC observation is claimed.
The implemented worker rechecks resource membership, licence and schema on each
acquisition. The stored sample is not permission to ignore future restrictions.

### Schema and identity

The report records **70 fields**: `_id` is an integer; the other 69 source fields
are text. The canonical schema fingerprint is
`da5fb4d8d7b80c203f06841c1667ab902220051631d63b607d2c1d23ffdf116f`.
The [v3 mapping manifest](../tools/ingestion/python/ingestion/mappings/acnc-register-v3.json)
provides every field's type, null rules, destination, attribution and suppression
handling; [coverage table](acnc-field-coverage.md) and
[website qualification](acnc-website-normalisation.md) provide review detail.

ABNs/postcodes remain strings. Dates, Y/N flags, all address lines and source
address roles have explicit transformations. Other names and operating-country
lists remain unsplit text where delimiter semantics are unqualified. Missing
values do not clear published fields. ACNC registration, establishment dates and
service geography remain separate facts. Resource-scoped CKAN `_id` is provenance,
not a stable cross-release identifier or the portal's UUID.

The six-record observation was staged as run 6 and replayed with v3 as run 8;
see [replay and publication closure](acnc-website-normalisation.md). Raw live
records remain private, outside Git. The committed
[ACNC parser fixture](../tools/ingestion/python/tests/fixtures/acnc-pages.json) and
[full-field fixture](../tools/ingestion/python/tests/fixtures/acnc-field-coverage.json)
are invented and do not replace the live evidence. Keep raw evidence under the
existing private staging controls; larger-scale retention/deletion and stable
cross-release identity remain separate qualification work.

Postcode 2730 is a discovery sample, not the Snowy Valleys boundary or proof of
service delivery. The broader [postcode discovery scope](snowy-valleys-postcode-scope.md)
contains 23 overlapping or directly adjacent Postal Areas, but has not been
acquired or qualified by this six-record observation. Apply the
[P01 policy](pilot-inclusion-policy.md) to each record. ACNC scheduling remains a
separate operator decision. Existing per-run caps are
five rows/page, two pages, bounded requests and metadata recheck; these are local
pilot limits, not a provider rate-limit entitlement.

## CSV fixture

Resource: `synthetic-community-csv` / `csv-pilot-v1`. Publisher: Community
organisations portal development fixtures. These files are authored for P04:

- [organisations.csv](../tools/ingestion/python/tests/fixtures/csv-pilot-v1/organisations.csv)
- [schema.json](../tools/ingestion/python/tests/fixtures/csv-pilot-v1/schema.json)
- [manifest.json](../tools/ingestion/python/tests/fixtures/csv-pilot-v1/manifest.json)

The manifest records version, provenance, fixed synthetic observation timestamp,
SHA-256 of the exact CSV/schema bytes, attribution, use basis, scope and expected
row outcomes. There is **no external provider licence**: these are project-authored
synthetic test records for internal development. This does not grant a repository
redistribution licence or permission to publish real provider data. The attribution
is “Synthetic community CSV fixture v1 — Community organisations portal development
fixtures; not real organisations.” `enabled` and `publication_eligible` are false.

The fixture contains nine records, UTF-8 without BOM, comma delimiter, double-quote
CSV escaping, LF line endings and an exact 16-column header. All cells start as
strings; blanks mean unknown/omitted. The schema specifies required values, enums,
identifier/date/URL rules and candidate destinations. It includes quoted commas,
non-ASCII text, a leading-zero postcode and incorporation number. The all-zero ABN
is an explicitly unverified synthetic placeholder, not a valid registry identity.

| Records                   | Expected P12 handling                                                                                         |
| ------------------------- | ------------------------------------------------------------------------------------------------------------- |
| csv-001, csv-002          | Two well-formed candidates; no-ABN groups are allowed; both still require inclusion/matching and field review |
| csv-003                   | Hold: branch shares an ABN with csv-002; preserve both identities                                             |
| csv-004                   | Hold: out-of-area service needs evidence and a delivering-organisation link                                   |
| csv-005                   | Hold: same name as csv-001 does not establish a duplicate                                                     |
| csv-006, csv-007, csv-008 | Quarantine: missing name, malformed ABN, unsafe website respectively                                          |
| csv-009                   | Hold: postcode `0800` stays text; no evidence of Snowy Valleys eligibility                                    |

Expected totals are **2 candidates, 4 held, 3 quarantined**. These are acceptance
expectations, not results of an implemented importer. Every record is synthetic;
none is approved for publication. `fixture:` evidence references deliberately do
not assert actual local activity or provider permission.

P12 should retain exact raw row values and file hash, use source/resource/native-ID
identity, and route only reviewed fields to the publication workflow. Row numbers
are diagnostics, never durable identity. Replaying identical bytes must not create
duplicates; a changed file needs a new observation/version. Reject mismatched
headers/metadata before staging, quarantine semantic row errors, and fail malformed
CSV when record boundaries cannot be recovered. A file containing quarantined
records is not a complete reconciliation snapshot. Never call the ACNC-specific
`stage_acnc`/`staging_sql` contract with these CSV records.

Before accepting a real CSV, replace fixture provenance with the actual publisher,
export/resource version, acquisition time, exact headers/hash, geographic scope,
native-ID stability, licence or written permission, public attribution, storage/
redistribution/removal conditions, and a responsible technical contact. Record
approval evidence and retention limits privately. Qualify a real permitted sample
against its provider-specific mapping; this contract is not an assumed NSW export
schema. No real file was supplied or approved as part of P04.

## ABN access preparation

The [ABN Lookup web services page](https://abr.business.gov.au/Tools/WebServices)
confirms free access following registration and agreement acceptance; an
authentication GUID is emailed to the applicant. No application or agreement
acceptance was submitted in P04, and no credential was sought from local secrets.
Credential availability is unconfirmed; the adapter remains unconfigured.

Prepared application purpose: “Verify exact ABNs associated with reviewed community
organisation candidates, preserving registry status, observation date and source
attribution. No automatic name-based merge or bulk geographic discovery.” The
platform owner supplies the applicant/contact details and completes the official
registration. Record the acceptance date, registered owner/contact and terms
reference privately; store the GUID in the worker secret store. Setting
`ABN_LOOKUP_GUID` is now implemented by the [P16 adapter](exact-abn-lookup.md).
Do not put it in public Svelte environment variables, committed fixtures or URLs
that are logged. No database service/admin key is needed to query ABN Lookup.

The [agreement](https://abr.business.gov.au/Tools/WebServicesAgreement) permits
relevant extracts subject to its conditions, prohibits misleading use and implied
Commonwealth endorsement, and requires reasonable immediate action to delete all
controlled copies of information withdrawn on notice. Keep contact details current.
P16 must cover raw evidence, versions, exports and caches as well as public fields;
existing portal suppression alone is not proof of that deletion capability. This
service agreement is separate from the ABN bulk-extract licence. The page displayed
version 9.9.7 when checked; that is a website label, not a separately verified
legal revision identifier. Retain the accepted terms with the actual application.

### P16 technical handoff

[Official methods](https://abr.business.gov.au/Documentation/WebServiceMethods)
identify `SearchByABNv202001` as the latest exact-ABN operation. Start new integration
there, recording operation and response version. The assessed upstream parser used
`SearchByABNv201408`; do not assume its shape matches the newer operation. Pin and
characterise the selected WSDL/response before adapting it. Request an exact ABN
string with `includeHistoricalDetails = "N"` for the initial current-state use case;
keep the authentication GUID server-side. The official method documentation links
the document-style WSDL/test service. No authenticated request was made in P04.

[Official response rules](https://abr.business.gov.au/Documentation/WebServiceResponse)
allow suppressed details and optional attributes; an absent name is not proof of
an empty search. Preserve main/business/historical-name distinctions and dates.
The [upstream assessment](acquisition-code-assessment.md) identifies
`entityDescription`/`entityTypeDescription` and `acnc_status`/`anc_status` mismatches
that need parser-to-mapping tests.

Before live enablement, P16 must demonstrate:

1. Namespace-aware fixtures for the selected operation, singleton/list shapes,
   suppressed details, status/name/date variants and missing optional attributes.
2. Explicit separation of invalid ABN, no match, invalid GUID, provider exception,
   malformed XML, timeout and successful response; failure never becomes closure.
3. Injected credentials, response-size bounds, finite timeouts and retry/backoff;
   proposed pilot caps: one request at a time, at most ten distinct ABNs, 10-second
   request timeout, 2 MiB response cap, three attempts and a 90-second job budget.
   These are proposed local limits; no provider quota was established in this review.
4. A small approved live set after GUID provisioning, with operation/version,
   observation time, response hash and redacted diagnostics. Include the official
   response documentation's edge-case references where appropriate, without
   treating synthetic ABNs as registered entities.
5. Private staging and reviewed projections; registry validity does not establish
   community purpose, service geography, ownership or a unique branch match.

## Verification

From `tools/ingestion/python`, run `python3 -m ingestion.field_coverage` to compare
the complete ACNC mapping against the retained observed schema. The P04 CSV check
below verifies file integrity, exact headers, record IDs and expectation counts;
it does not implement importer validation or assert provider approval.

From the repository root:

```sh
python3 - <<'PY'
import csv, hashlib, json
from collections import Counter
from pathlib import Path
p = Path('tools/ingestion/python/tests/fixtures/csv-pilot-v1')
m = json.loads((p / 'manifest.json').read_text())
s = json.loads((p / 'schema.json').read_text())
for name, digest in m['files'].items():
    assert hashlib.sha256((p / name).read_bytes()).hexdigest() == digest, name
with (p / 'organisations.csv').open(encoding='utf-8', newline='') as f:
    reader = csv.DictReader(f, strict=True)
    assert reader.fieldnames == [column['name'] for column in s['columns']]
    rows = list(reader)
assert len(rows) == m['row_count'] == 9
assert all(None not in row and None not in row.values() for row in rows)
assert [r['source_record_id'] for r in rows] == [r['source_record_id'] for r in m['expected_rows']]
assert len({r['source_record_id'] for r in rows}) == len(rows)
assert Counter(r['disposition'] for r in m['expected_rows']) == m['expected_counts']
assert rows[8]['postcode'] == '0800' and rows[1]['incorporation_number'] == '0000123'
assert m['synthetic'] and not m['enabled'] and not m['publication_eligible']
print('P04 CSV integrity: 9 rows; expected 2 candidates, 4 held, 3 quarantined.')
PY
```
