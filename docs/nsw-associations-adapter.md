# NSW incorporated-associations adapter

Status: implemented locally and disabled. Reviewed 25 September 2026.

## Boundary

The Phase 7 adapter searches the ordinary unauthenticated NSW Fair Trading
Incorporated Associations Register by configured postcode and emits the private
`registry-seed-v1` contract. It does not connect to the portal database, decide
community relevance, link by name, create an organisation, or publish anything.

NSW Government describes the online register as containing an association's name,
incorporation number, incorporation date and registration status. The current search
markup also presents organisation type and registered-office address. Collection of
the latter fields remains subject to recorded access/reuse approval; the adapter
does not infer service coverage from an office postcode.

Official references:

- [NSW incorporated associations register](https://www.nsw.gov.au/business-and-economy/incorporated-associations/nsw-incorporated-associations-register)
- [Public search](https://applications.fairtrading.nsw.gov.au/assocregister/)
- [Forms and official extracts](https://www.nsw.gov.au/business-and-economy/incorporated-associations/incorporated-associations-forms-and-fees)

Reachability and current markup were checked without submitting a search on 25
September 2026. That check is not legal approval for automated collection. Before a
live run, the operator must record the approval reference, contact identity,
permitted fields, attribution and retention basis, then explicitly enable both the
local configuration and the private source row.

## Safety contract

- One independently paginated search is run per configured postcode.
- ASP.NET state, result container, row identity/status and next-page controls are
  checked on every page; an unexpected page is a failed part, never an empty result.
- Requests use a descriptive contact-bearing user agent, at least two seconds of
  pacing, finite response/operation limits, no redirects and no retry loop.
- Pagination repetition, conflicting next controls, duplicate incorporation numbers,
  response-size overflow, partial searches and the page budget fail the release.
- Candidate identity is exactly `(incorporated_association, AU-NSW, source number)`,
  represented as `AU-NSW:<number>`. Names are assertions, never match keys.
- A complete release means complete only for every configured postcode search. It
  is not a complete NSW-register snapshot and cannot prove local service delivery.
- Output files are new, private (`0600`) artifacts. Staging remains a separate SQL
  operation; triage, promotion, campaign readiness and dual-controlled publication
  remain separate decisions.

## Qualification and operation

Copy the example configuration outside the repository and replace every approval or
contact placeholder. Keep `enabled=false` until approval and a permitted current
markup sample have been reviewed.

```bash
cd tools/ingestion/python
.venv/bin/python -m unittest tests.test_nsw_associations -v
.venv/bin/python -m ingestion.live_nsw_associations \
  --config /approved/private/nsw-associations.json \
  --enable \
  --output-dir /approved/private/nsw-run-YYYYMMDD
```

Review `manifest.json`, `candidates.json` and all failed/empty postcode parts before
running the generated `stage.sql` with the restricted ingestion-worker procedure.
Do not stage a partial release as an initial-seed campaign artifact. Enabling
recurrence additionally requires an unchanged refresh, status-change, withdrawal,
partial-run and rollback exercise described by P36.

## Tests

The synthetic suite covers ASP.NET state extraction, result parsing, two-page
pagination, scoped identifiers, empty-search fencing, markup drift, duplicate
identities, page-budget exhaustion and registry-seed manifest generation. It contains
no copied register records or personal contact information.
