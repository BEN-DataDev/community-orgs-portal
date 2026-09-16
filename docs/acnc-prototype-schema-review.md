# ACNC offline prototype: schema review

Implemented 16 September 2026. This is a fixture-based design check, not a live import.

Follow-up: the [private staging implementation](private-staging.md) now validates
a live six-record ACNC sample and tests a staging migration in a disposable database.
The initial prototype results and mapping decisions below remain its design basis.

## Result

The [Python prototype](../tools/ingestion/python/README.md) produces
[normalised JSON](../tools/ingestion/python/examples/acnc-normalised.json) from two
synthetic CKAN records. Fifteen local tests pass, including the upstream address-loss
regression, identifiers, pagination failures, scope validation and deterministic replay.

The prototype has no external dependencies or network/database side effects. Its
provenance manifest identifies upstream files and the pinned commit. Code reuse
rights are recorded as user-authorised local adaptation, not an inferred open-source
licence. External redistribution remains a separate licence/ownership check.

## Mapping decisions before migrations

| Prototype assertion                          | Existing portal destination                        | Decision                                                                                                                                    |
| -------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `entity_name`                                | `organisations.entity_name`                        | Suitable after identity review; do not overwrite a protected manual revision                                                                |
| `abn`                                        | `legal_details.abn`                                | Format-only validation is insufficient for verified identity; store verification/source evidence separately                                 |
| `administrative_address`                     | `contact_info.physical_address` / `postal_address` | Route by qualified address type; keep structured lines/locality/postcode in staging. Do not create a service location from a postal address |
| `website`                                    | `contact_info.website`                             | Add URL validation and reviewed field precedence at publication                                                                             |
| `date_established_source`                    | `organisations.date_established`                   | Explicit source date parsing required; example is day/month/year, not a database-ready date                                                 |
| `charity_registration_date_source`           | `legal_details.acnc_registered_date`               | Keep separate from establishment and incorporation dates; qualify actual source format                                                      |
| `financial_year_end_source`                  | `financial_info.financial_year_end`                | Example is recurring day/month, whereas destination is a full date. Do not invent a year; resolve representation before mapping             |
| `other_names_source`                         | `aliases`                                          | Raw string does not establish delimiter or business/trading alias type. Retain until source notes and mapping are verified                  |
| Provenance, raw hashes, run/scope/completion | No existing equivalent                             | Add private ingestion structures before database import                                                                                     |

The output contains no asserted charity status because the fixture supplies no such
field. The dataset's title alone is not used to fabricate booleans or current status.
Unknown dates/status values are not translated into false or automatic deletions.

## First staging migration proposal

The sample supports the following minimal foundation, using the names in the strategy:

1. `sources`: resource/schema identity, approval, terms and attribution metadata.
2. `ingestion_runs`: explicit scope, parser version, timestamps, completion and counts.
3. `source_records` and versions: `(source_id, resource_id, native_id)` scoped identity,
   raw reference/hash and observations; no ABN-level automatic merging.
4. `field_assertions`: raw typed values and source record/version references.

Keep these private. Add record links, change sets, revisions and publication controls
before writing portal tables. Do not add global ABN uniqueness or make source `_id`
an organisation UUID. Source row IDs must be qualified for stability across snapshots.

Raw fixture data is inline for reviewability. Live payloads should use the private
storage and retention policy described in the ingestion strategy. Partial/failed
runs must be excluded from reconciliation. Even a complete filtered query cannot
prove absence outside its recorded scope.

## Status against R01–R04

| Task | ACNC prototype result                                                           | Still outstanding                                                                |
| ---- | ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| R01  | Source commit, paths, hashes and adaptation basis recorded                      | General redistribution licence/ownership confirmation                            |
| R02  | Isolated standard-library Python client and CLI; no application/service startup | Live transport packaging and other provider adapters                             |
| R03  | ACNC address, identifier, failure and pagination fixtures pass                  | ABN mapping/namespace and NSW pagination tests; real permitted provider fixtures |
| R04  | Versioned JSON envelope and reproducible sample implemented                     | Consumer-side contract validation, private staging and live-source qualification |

This completes the requested **offline ACNC first step**, not all multi-provider
qualification tasks. Next: qualify a current permitted ACNC sample/resource and
implement private staging informed by these mapping decisions. No schema migration
has been applied by this prototype.
