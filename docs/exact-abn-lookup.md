# Exact-ABN lookup (P16)

Implemented as a standalone Python acquisition command. Authenticated live
qualification remains pending: no access GUID or approved live set was supplied.
Missing access produces `pending_credentials`, never an accepted identifier.

## Contract and acquisition

The adapter adapts the assessed upstream ABRClient and field extraction approach;
provenance and source hash are in `tools/ingestion/python/upstream-manifest.json`.
It uses SOAP 1.1 `SearchByABNv202001` with `includeHistoricalDetails=N`. The public
[official WSDL](https://abr.business.gov.au/abrxmlsearch/AbrXmlSearch.asmx?WSDL)
was retrieved on 2026-09-18 and is pinned under `tools/ingestion/python/contracts`.
No runtime WSDL download, Zeep, Flask, Redis or database credentials are required.

The namespace-aware parser accepts only the selected operation and response
version. Repeated fields always remain arrays, including singletons. Names retain
their type and effective dates; status, replacement identifiers, addresses and
optional/nil fields remain in the private entity tree. The projection maps
`entityType/entityDescription` to `entity_type_description` and `ACNCRegistration`
to `acnc_registration`, avoiding both upstream parser/transformer mismatches.

A nameless response can succeed: the
[official response rules](https://abr.business.gov.au/Documentation/WebServiceResponse)
allow suppressed details. Success requires the exact requested ABN and a native
status. It does not establish purpose, service geography, ownership, branch match,
or organisation closure. Empty or unrecognised payloads are malformed, not absence.
[Documented exceptions](https://abr.business.gov.au/Documentation/Exceptions)
distinguish no match and invalid access; unknown errors remain provider exceptions.

Limits are one request at a time, ten input ABNs, duplicate normalized ABNs fetched
once, three attempts, ten seconds per request, two MiB per response, thirty total
attempts and a shared ninety-second budget. HTTP 429/transient 5xx and transport
failures use bounded exponential backoff. Redirects are refused. Application
exceptions are not retried. Invalid ABNs fail locally using ASCII/checksum checks.
Timeouts, malformed XML, provider errors, no match and unavailable credentials are
separate outcomes; none creates closure or deletes existing assertions.

## Run and review

From `tools/ingestion/python`, an offline pending-access run is:

```sh
python3 -m ingestion.exact_abn --abn '34 241 177 887' --output-dir /tmp/abn-review-new
python3 -m unittest discover -s tests -q
```

The example is an official edge-case reference, not a claim of live verification.
For an approved live set, provision `ABN_LOOKUP_GUID` in the worker environment and
add `--enable`; repeat `--abn` for each reviewed input. Do not place the GUID in
command arguments, URLs, public environment variables or committed files. Nonzero
exit means at least one result was not successful; stdout contains only outcome
codes and request count. The output directory must not already exist.

The command writes `evidence.json` and a SHA-256 manifest in a mode-0700 directory,
with mode-0600 files. Evidence includes operation, parser/response/WSDL versions,
observation time, original response hash, registry timestamps and attribution.
The parsed entity subtree retains source values. Raw response bytes are discarded:
they can echo the authentication GUID in the original request. Provider error text
is never logged or persisted; credential echoes in retained fields are rejected.
Do not feed this envelope to the ACNC-specific SQL staging loader.

Every result is pending review. Use the existing
[P14 operator evidence review](deterministic-matching.md#operator-evidence-review)
workflow to inspect the holder and exact key before any identity RPC. Use a private
bundle reference and response hash as evidence, with authority, holder name,
observation time and native status/dates. An operator supplies
`qualified_registry_review: true` only after actually reviewing qualified evidence;
the adapter never manufactures this attestation. A suppressed holder may need
additional registry evidence. Failed and unavailable lookups cannot verify keys.

## Retention and live qualification

Keep bundles in one private, inventoried evidence location outside the repository;
the manifest identifies contained ABNs and files. This command creates no database
rows, caches, public projections, exports or historical copies. On a withdrawal
notice, delete the entire affected bundle (including manifest), then delete any
inventoried copies. Before copying evidence into an operator RPC, export, backup
or another store, record its location and establish that store's actual deletion
procedure. Existing portal suppression does not remove those copies. Until this
end-to-end procedure and accepted terms are recorded, keep live qualification
pending; the command's enable flag does not attest legal approval.

Live completion requires the registered owner to record accepted service terms,
provision access, approve at most ten exact ABNs and retain redacted results.
Include suppressed, replaced/reissued and multiple-status/name cases where
appropriate. Check native response dates, holder identity, attribution and the
withdrawal process across all retained copies. No authenticated lookup, legal
acceptance, hosted migration or automatic identity verification was performed
for this implementation.

## Implementation verification

On 2026-09-18, all 87 Python ingestion tests passed, including 13 P16 tests for
checksum validation, suppressed details, repeated names/statuses, replacement
identifiers, nil values, mapping keys, SOAP/WSDL request shape, malformed XML/DTD,
exception separation, timeouts/retries/deadlines, redirects, byte/request caps,
credential echoes, private artifact permissions and overwrite refusal. The pinned
WSDL hash was verified. An offline CLI run returned `pending_credentials`, exit 1
and zero HTTP requests. Synthetic fixtures do not establish live provider parity.
