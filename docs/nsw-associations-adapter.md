# NSW incorporated-associations adapter

Status: live transport/markup, owner access/reuse basis and capped-result
partitioning qualified; complete full-status and registered-only 23-postcode
releases finished on 28 September 2026. The registered-only release is staged
privately as hosted release 3; review, promotion and publication remain pending.
Reviewed 28 September 2026.

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

The current transport and markup were qualified with one non-retained postcode 2730
search on 27 September 2026; the contact-free evidence summary is in
[`nsw-associations-live-qualification.json`](nsw-associations-live-qualification.json).
The portal owner authorised bounded collection and reuse on 27 September 2026 under
the active NSW Open Data Policy and ordinary public-register access. This is recorded
as `OWNER-2026-09-27-NSW-OPEN-DATA`; it is an internal accountable decision, not a
claim of bespoke NSW agency approval. Retained runs must keep the recorded public
field scope, attribution, private evidence controls and removal/correction duties.
They must explicitly enable the local configuration, pass `--enable`, and use an
enabled private source row.

## Safety contract

- Independently paginated searches are run for every configured postcode and the
  configured non-empty status subset, always constrained to organisation type
  `INCORASSOC`. Statuses use the register's canonical order so manifests and resume
  evidence are deterministic. The initial-seed profile configures only `REGISTERED`;
  qualification may configure all six statuses.
- ASP.NET state, result container, row identity/status and the register's qualified
  top/bottom next-page control pair are checked on every page; an unexpected page
  is a failed part, never an empty result.
- The qualified zero-result state requires a visible refine-search section, no
  result container, no organisation detail links and no enabled next control.
- Requests use a descriptive user agent with a stable email or HTTPS contact and
  at least two seconds of global pacing, including between isolated postcode
  sessions. Requests have finite response/operation limits and no retry loop. The transport permits
  only the register's observed same-origin `302` transition from a form POST to the
  fixed `RegistrationSearch.aspx` results GET; every other redirect fails closed.
- Pagination repetition, conflicting next controls, duplicate incorporation numbers,
  response-size overflow, partial searches and the page budget fail the release.
- A search returning the configured 200-record provider cap is never accepted as a
  complete leaf, even when the final page hides its Next control. The adapter
  recursively replaces it with non-overlapping inclusive registration-date ranges.
  Every terminal leaf must return fewer than 200 records. A capped parent containing
  a record without a registration date fails closed because that record could not be
  proven present in the child ranges.
- Candidate identity is exactly `(incorporated_association, AU-NSW, source number)`,
  represented as `AU-NSW:<number>`. Names are assertions, never match keys.
- A complete release means complete only when every status/date query leaf for every
  configured postcode terminates below the cap. It is not a complete NSW-register
  snapshot and cannot prove local service delivery.
- Output files are new, private (`0600`) artifacts. Staging remains a separate SQL
  operation; triage, promotion, campaign readiness and dual-controlled publication
  remain separate decisions.

## Qualification and operation

Copy the example configuration outside the repository and replace every approval or
contact placeholder. Keep `enabled=false` until the owner decision has been recorded. A live
run requires `approved_access_reuse=true`, `enabled=true` and the explicit
`--enable` flag; placeholder evidence is rejected.

`statuses` is a required, non-empty, unique subset of `AMALG`, `CANCELLED`,
`LIQUIDATIN`, `REGISTERED`, `TRANSFER` and `ADMNSTRATN`, in that canonical order.
It is part of the immutable release scope. The checked-in example selects only
`REGISTERED` for the initial seed and recurring comparable baseline.

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

If a provider timeout makes a retained run partial, pause requests and resume later
into a new output directory with `--resume-from /private/prior-run`. Resume keeps
only the leading terminal query leaves whose last page completed with no next
control. It restarts the exact failed status/date leaf and queues every later leaf;
it never resumes inside an ASP.NET pagination session or overwrites prior evidence.

The initial expanded attempt established that the public interface silently
terminates large searches at 200 records. The partitioned replacement release
`nsw-694bfbc3-d570-4c05-8a17-1596df5126b0` completed on 28 September 2026 for all
23 configured postcodes with 2,519 unique candidates, 373 retained terminal pages,
10 recorded cap splits and no final errors. In particular, postcode 2640 yielded
426 candidates and postcode 2650 yielded 793, demonstrating why the former
200-record results were incomplete. This is complete only for the configured
postcode/status/date query tree, not for NSW statewide or for community relevance.
The full-status qualification artifact remains deliberately unstaged: its historical
statuses are audit evidence, not the initial seed. The existing restricted
`community_orgs_acquisition` login assumes `ingestion_worker`; it was reused for the
registered-only staging operation without granting direct private-table access.

## Initial seed and recurring comparison profile

The complete 2,519-candidate acquisition is retained as private qualification and
audit evidence. It is not the initial database seed cohort. The initial NSW seed is
restricted to records returned as organisation type `INCORASSOC` and status
`REGISTERED`; for this profile, “current” means the provider's `REGISTERED` status.
The completed acquisition contains 1,420 such candidates. Cancelled,
transferred, amalgamated, in-liquidation and under-administration results are not
initial-seed candidates. Registered-only release
`nsw-01804a60-a82d-4135-9d0f-cee6d300c7e5` completed all 23 postcodes with
1,420 unique candidates, 161 terminal parts, 7 cap splits and no final errors. Its
native-ID set exactly equals the `REGISTERED` subset of the full-status release.
It is privately staged as hosted registry-seed release 3 through the six-batch
resumable boundary. Idempotent finalization returned the same release ID and cleared
the temporary upload candidates. No triage, promotion or publication occurred. Do
not edit the completed full-status evidence bundle or stage its 1,099 non-Registered
records as the initial seed.

Recurring discovery uses the same postcodes, organisation type and `REGISTERED`
status as the initial registered-only baseline. Compare only two complete,
comparable releases with the same scope and query-plan version:

- a native ID newly present is a new private candidate;
- a native ID present in both releases may produce field-level changes; and
- a native ID absent from the newer release becomes `verification_required`.

Absence is not a cancellation, transfer, amalgamation or removal fact. An
association may have changed its registered-office postcode and left the configured
search scope. Verify an absent native ID by exact incorporation number against the
current register and its available statuses before proposing a status change,
out-of-scope transition, suppression or withdrawal. A partial or failed harvest
cannot drive any absence inference. No comparison automatically deletes, closes,
suppresses or unpublishes an organisation.

## Tests

The synthetic suite covers ASP.NET state extraction, result parsing, two-page
pagination, scoped identifiers, organisation-type/status filtering, empty-search
fencing, markup drift, duplicate identities, page-budget exhaustion, recursive cap
splitting, missing-date fencing and status/date-leaf resume. It contains no copied
register records or personal contact information.
