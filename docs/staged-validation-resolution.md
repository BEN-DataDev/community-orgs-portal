# Cross-source staged validation resolution

Decision date: 23 September 2026

Status: implemented and verified locally on 23 September 2026; hosted migration,
worker rollout and run 30 production replay remain pending

## Decision and scope

Every staged source must expose every recoverable validation failure through one
operator UI. The workflow covers failed fields and failed records from ordinary
ingestion runs, plus validation failures attached to registry-seed candidates and
releases. It is not an ACNC-specific website exception.

The source observation, raw value, original run and original completion state are
immutable. An operator resolution never changes a partial run to complete. After
all eligible blocking issues are resolved, the system revalidates the complete
record set and creates a separately versioned derived run. That run enters the
existing identity, field approval and publication workflow only if it completes
without quarantine or acquisition errors.

This capability does not allow an operator to override source scope, changed
schema, licence/qualification, incomplete acquisition, duplicate identity or
complete-snapshot checks. Those failures require source requalification, mapping
work or a new acquisition.

## Structured issue contract

Adapters must emit structured issues rather than relying on a combined diagnostic
string. Legacy `quarantine` and `errors` arrays remain readable during migration.
Each issue has this logical shape:

```json
{
	"subject": { "native_id": "2242", "row": 14 },
	"field": {
		"source_key": "Charity_Website",
		"canonical_key": "website"
	},
	"code": "website.scheme_missing",
	"category": "field_format",
	"severity": "blocking",
	"source_value": "www.example.org/path",
	"validator": { "name": "http_url", "version": "2" },
	"allowed_resolutions": ["correct", "omit", "defer", "reject_record"]
}
```

The contract supports issues without a field for record, release and acquisition
failures. Required categories are:

- `field_format` and `missing_required_field`;
- `duplicate_identity` and other record-integrity failures;
- `record_scope`;
- `source_schema` and `mapping_unknown`;
- `acquisition_error`; and
- `licence_or_qualification`.

Every issue records a stable code, severity, source location, raw-evidence hash,
validator name/version and permitted resolution modes. Display text is not an
identifier and may change without merging distinct failure classes.

## Private database model

Add the following RLS-protected tables under `ingestion`; browser and service roles
receive no direct table access:

| Table                          | Purpose                                                                                       |
| ------------------------------ | --------------------------------------------------------------------------------------------- |
| `validation_issues`            | Immutable issue, source artifact, subject, field, original value, validator and evidence hash |
| `validation_resolutions`       | Current revision-fenced operator decision and proposed/canonical value                        |
| `validation_resolution_events` | Append-only history of every decision revision                                                |
| `validation_attempts`          | Server-side validation result for a proposed value, including validator/mapping versions      |
| `validation_replays`           | Parent artifact, exact resolution revisions and the derived run/release                       |

A validation issue belongs to exactly one staged artifact: an ordinary
`ingestion_run` or a `registry_seed_release`. It may identify a native record and
source row, and may identify a source field and canonical field. Cross-artifact
polymorphism must be constrained so an issue cannot silently lose its parent.

Resolution decisions are `correct`, `omit`, `defer` or `reject_record`:

- `correct` supplies a proposed value. The authoritative server validator must
  accept it and record the canonical typed value.
- `omit` is available only for a mapping-declared optional field. It means the
  derived record makes no assertion for that field; it is not a deletion.
- `defer` retains the issue as unresolved private evidence.
- `reject_record` intentionally excludes the record from the derived artifact.
  The replay records the exact rejected issue revision and downgrades
  `complete_snapshot` to `false`, so the rejected subset cannot drive absence
  reconciliation.

There is no unrestricted `accept_as_is`. A mapping may define a manual-evidence
validator, but its result must still satisfy the destination type and an explicit
source-specific contract. Operator identity, time, required note, expected
revision, proposed value, canonical value, validator/mapping versions and optional
evidence reference are retained for every decision.

## Operator UI

**Admin → Import review** gains a **Validation issues** view with:

- source, run/release, field, category, severity and decision filters;
- accepted, blocking, deferred and non-resolvable counts;
- the immutable raw value, record context, failure code/reason and validator;
- a type-appropriate correction control and safe suggested transformation;
- a server-side **Validate proposed value** action;
- `correct`, `omit`, `defer` and `reject record` actions limited by the issue
  contract;
- required notes, actor/timestamp and revision history; and
- a **Create corrected run** action available only when replay gates pass.

External URL candidates use an HTTP(S) allowlist and open with `noopener` and
`noreferrer`. Opening a URL does not validate ownership, relevance or source
identity. The operator records that evidence separately. Arbitrary source text is
never inserted into an executable URL, HTML or SQL context.

The UI must say **Create corrected run**, never **Mark complete**. It presents
structural/scope/acquisition failures for diagnosis without offering a manual
override. Concurrent saves use expected revisions and fail closed on stale state.

## Replay and publication gates

Replay applies an exact, immutable set of resolution revisions to raw evidence and
runs the current approved adapter/mapping over every affected record. It must:

1. verify that raw evidence is still retained and its hash matches the issue;
2. re-run all non-rejected records through record and field validation, not only
   the edited field, and retain exact audit evidence for intentional rejections;
3. preserve source identity, observation time and parent-run lineage;
4. write a new parser/mapping-versioned record version and derived run;
5. keep the parent run and its quarantine unchanged;
6. produce `complete` only with zero quarantine and zero acquisition errors; and
7. downgrade a derived artifact containing intentional rejections to
   `complete_snapshot=false`, prohibiting absence reconciliation.

The derived run remains `publication_eligible=false`. Existing identity review,
source enablement, selected-field approval, suppression, manual-edit protection
and publication checks remain mandatory and cannot be collapsed into validation.

## Access, retention and withdrawal

Ingestion operators may inspect issues, validate proposals and record resolutions
through narrow security-definer RPCs. Platform administrators control source and
mapping qualification. Workers stage issues and execute fenced replay; neither
role receives direct portal-table writes through this feature.

Raw failed values, proposed corrections, notes and validation evidence are private
source evidence. They follow the parent source's retention and withdrawal policy.
Redaction and expiry must cover issues, attempts, current resolutions, event
history and replay artifacts without deleting the minimal audit fact required to
prove that a decision occurred.

## Compatibility and rollout

P34a is implemented in these increments:

1. Add the tables, grants, revision-fenced RPCs and structured issue contract.
2. Re-run the applicable versioned validators over retained legacy raw evidence to
   materialise field-level issues. Where raw evidence is unavailable, preserve the
   old diagnostic as a non-resolvable record-level legacy issue rather than
   guessing a field. Backfill run 30's seven ACNC website failures as the first
   production check.
3. Add the generic validation-issues UI and server validators.
4. Add ordinary-run replay with immutable lineage and complete-run gates.
5. Add registry-seed release/candidate issue parents and promotion gates.
6. Update ACNC, approved CSV, ABN/registry seed and future NSW adapters to emit
   structured issues directly.
7. Apply retention, suppression, access, concurrency and browser regression suites.

## Local implementation

Migration `20260924010000_staged_validation_resolution` implements the five-table
private model, structured-issue staging for ordinary and registry-seed artifacts,
revision-fenced validation/resolution RPCs, promotion gates, retention/suppression
redaction and a fenced corrected-run queue. The migration materialises retained
legacy diagnostics and recognises retained ACNC `Charity_Website` failures as
field-addressable `website.format` issues; this is the path that will backfill run
30 when the migration is applied to the hosted database.

**Admin → Import review → Validation issues** provides filters, immutable evidence,
server validation, permitted decisions, history and **Create corrected run**. The
acquisition worker claims replay requests, verifies the exact issue revisions and
raw-evidence hashes, re-runs the source adapter across every non-rejected retained
record, and can stage only a separate complete private run with no errors or
quarantine. Intentionally rejected records are excluded, counted and retained as
immutable replay evidence.

Local verification covers database access denial, structured staging, stale
revision rejection, immutable history, non-overridable failures, fenced replay,
parent/derived lineage, publication isolation and retention redaction. The Python
suite covers ACNC and approved-CSV structured issues and full-record replay.

## Acceptance

P34a is complete only when tests demonstrate:

- every failed field/record from every staged source is visible to an authorised
  operator, while unauthorised and public users receive no evidence;
- field corrections are validated by the same versioned rules used by ingestion;
- non-overridable scope/schema/licence/acquisition failures have no acceptance
  action;
- stale decisions and changed raw evidence fail closed;
- partial parents remain immutable and cannot publish;
- replay produces a separate, attributable run and cannot invent snapshot
  completeness;
- no resolution, replay or retry creates or changes a public organisation; and
- run 30 can be replayed from its retained evidence after all seven website issues
  are resolved, with zero quarantine and no change to the original run.
