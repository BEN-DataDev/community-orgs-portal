# Approved CSV importer (P12)

Implemented and deployed on 18 September 2026; see the hosted verification below. The offline Python command validates a
qualified file and emits the existing versioned private staging contract plus
optional SQL. Valid rows appear at `/admin/ingestion`; matching, field approval and
publication use the existing operator workflow. Browser upload and scheduled CSV
acquisition are not part of this increment. Real-provider onboarding is deferred
until an approved CSV is received; P12 remains complete.

## File and qualification contract

Use the columns in the [P04 schema](../tools/ingestion/python/tests/fixtures/csv-pilot-v1/schema.json).
The schema's original status describes its P04 preparation; P12 now implements it.
UTF-8 (optional BOM), quoted commas and multiline fields are supported. Column order
may vary, but every column must appear exactly once. Files are bounded to 5 MiB,
10,000 records and the Python CSV reader's default 128 KiB field limit. Invalid
encoding, unrecoverable CSV syntax, column mismatches and manifest count/hash
mismatches reject the whole file before an envelope is written.

The [fixture manifest](../tools/ingestion/python/tests/fixtures/csv-pilot-v1/manifest.json)
is the metadata template (`p04-csv-qualification-v1`). For an actual approved export:

- Supply the real source/resource identity, publisher, attribution, observation time
  and basis, technical contact and retention requirements.
- Set `synthetic: false`, `access_status: "approved"`, and keep
  `publication_eligible: false`. Include `approved_by`, `approved_at` (UTC RFC3339)
  and `access_evidence_ref`. These record an existing approval; the importer does
  not establish provider permission.
- Record licence/use `basis`, `permitted_use` and `terms_ref`, plus an identifier
  where applicable. Record scope `kind`, `intended_pilot` and
  `complete_snapshot: false`. V1 never infers withdrawal from an absent row.
- Set `row_count` and `files[CSV basename]` to the exact file's SHA-256. Fixture
  expectations, creation dates and other descriptive metadata do not grant access.

Do not convert the synthetic fixture into live content. It remains development-only,
with a blocking error even when every row is valid. P04 fixture files/hashes are
unchanged. Real provider qualification, including a NSW export, remains separate.

## Import and review

From `tools/ingestion/python`:

```bash
python3 -m ingestion.approved_csv \
  --input /secure/import/organisations.csv \
  --manifest /secure/import/manifest.json \
  --output /secure/import/envelope.json \
  --sql-output /secure/import/stage.sql
```

Exit status is **0** for a complete file, **1** for a staged-evidence envelope with
quarantine/development restrictions, and **2** for file/metadata rejection. The
command opens no network or database connections. Output JSON and SQL contain
private source evidence; retain them under the approved source policy.

Deploy migration `20260917230927_approved_csv_import.sql` before staging. A database
administrator registers the source/resource in `ingestion.sources`, places the
exact reviewed manifest under `metadata.csv_qualification`, and explicitly enables
the source. Preserve other metadata; populate the existing `public_title`,
`public_url`, `public_licence`, `public_licence_url` and `synthetic` metadata used
by public attribution. Only publish approved public attribution links. The
manifest's `enabled` field is descriptive and never enables a database source.
Register each new approved file manifest before staging it; this deliberately
requires qualification per export. To replay an older export after qualification
has changed, its exact manifest must be registered again.

Apply the generated SQL using a connection authorised to assume `ingestion_worker`,
an explicitly selected database, and `psql -X -v ON_ERROR_STOP=1 -f stage.sql`.
Browser roles cannot execute `ingestion.stage_csv`; the worker cannot register or
enable sources. The RPC checks that the envelope qualification matches the
administrator's metadata, and keeps the P09 expiry/replay protection. It trusts the
restricted worker to execute the validated parser, as with ACNC.

The command records raw field values, hashes, native IDs, source references,
observation/source modification times, parser/mapping versions and qualification.
File bytes are hashed, while decoded row evidence is retained as private JSONB;
retain the original file separately when the approved evidence policy requires it.
Identities are `(source_id, resource_id, source_record_id)`; row numbers are only
1-based diagnostics. Duplicate IDs quarantine **all** occurrences. Format-invalid
ABNs, URLs, postcodes, states, timestamps and incomplete incorporation identifiers
are quarantined with reasons. No ABN is required or declared registry-verified.

Only name, ABN and website are mapped for field publication. Other supplied values,
including jurisdiction/number, leading-zero postcodes, classifications, scope and
review holds, are visible as private unmapped `csv_*` assertions. Branches,
services, duplicate names and uncertain scope require operator investigation and
an explicit link/create/defer/reject decision. A candidate is not a finding of
geographic eligibility. Incorporation-number matching and publication are deferred
to the identifier-mapping work; this importer does not merge on name or ABN.

A run containing any quarantined row is partial: **none of its rows can be
approved for publication**. Today, correct the source export and qualify/import a
new file. Approved P34a work will also permit eligible field/record issues to be
resolved through the shared
[staged-validation workflow](staged-validation-resolution.md), followed by full
revalidation into a separate derived run. It will not mutate the partial parent or
permit source/file/scope/qualification failures to be overridden.
Clean approved exports still require identity review, selected-field approval and
explicit publication. Blank fields emit no assertions and never delete values.
Existing manual-edit, suppression, revision and publication replay guards apply.

## Verification and deployment status

Validation passed: **59 Python tests**, **36 unmodified migrations** in disposable
PostGIS 17, all eight existing SQL suites, the CSV integration checks and concurrent
owner-revocation checks. The Python suite covers the nine-row P04 outcomes (2 candidates, 4 holds,
3 quarantine), metadata rejection, file hashes/counts, malformed CSV, encoding,
multiline/Unicode/BOM input, duplicate identities, row validation, omission and
repeatability. The disposable database runner uses the real parser's envelopes:

```bash
# From tools/ingestion/python
python3 -m unittest discover -s tests
# From the repository root; requires local Docker/PostGIS image
python3 scripts/test-operator-access-db.py
```

Database checks exercise qualification mismatch, source disablement, private
grants, quarantine retention, repeated runs/versions, no public writes before
publication, partial-run approval denial, explicit approved publication, no owner
grant, publication replay and immutable replay after raw expiry. Existing access,
review, publication and P09 retention suites run alongside these checks.

The migration is now deployed; see the hosted verification below. Qualify an actual
provider export before live staging. Forward repair: disable the CSV source
to stop staging/publication; retain runs and audit history. The migration changes no
ACNC functions or public tables.

## Hosted deployment preflight — 18 September 2026

Confirmed destination: Supabase project `gqltsfijginclwszrcfj`
(`https://gqltsfijginclwszrcfj.supabase.co`). All prerequisite migrations through
`private_raw_retention` are present. Both CSV functions and the CSV migration are
absent. Existing state is two ACNC source registrations, eight retained runs,
eight publications and seven organisations; ACNC scheduling remains off.

Automatic approval review rejected the attempted `approved_csv_import` migration:
explicit authorization for production schema/security-definer/grant changes to
this destination was required. No migration was applied at that preflight stage.
The subsequently approved change creates
two private functions, permits the staging worker to call the qualified CSV entry
point, and makes no source, schedule or public-data changes.

The deployment procedure prepared at preflight was to apply the migration after
destination-specific approval and run rollback-only verification. The hosted-compatible
command is now `python3 scripts/build-csv-test-sql.py --hosted`. This checks the actual parser,
staging, review and publication path with synthetic test records; all test rows
roll back (identity sequences may advance). Confirm the fixed test source and test
user are absent before executing. Then check function grants, migration history
and unchanged source/schedule/public-data state. Align the local migration filename
with the version assigned by the hosted migration tool. No web application release
is required for this CLI/database increment.

No real CSV export or provider approval evidence is present in the repository or
registered source metadata. A provider file/path/URL and its access/reuse evidence
are still needed to complete real-export qualification.

## Hosted deployment and verification — 18 September 2026

Following explicit destination-specific user approval, applied `approved_csv_import`
to project `gqltsfijginclwszrcfj` as **20260917230927**. The local migration filename
is aligned with that hosted version. This resolves the approval block recorded
in the preflight section above. No web deployment is needed.

The hosted rollback-only integration passed: real parser envelopes, qualification
and disabled-source rejection, six accepted rows and three quarantines, run/version
replay, partial-file approval denial, explicit field approval/publication, publication
replay, no imported ownership and immutable replay after raw expiry. Generate the
hosted test with `python3 scripts/build-csv-test-sql.py --hosted`.

The fixture now supplies email and creation/update timestamps required by the
hosted auth-to-profile trigger. The management connection cannot assume the worker
role: hosted mode checks worker execute grants and invokes staging through the
management connection; authenticated review/publication still uses `SET ROLE`.
Actual worker role execution remains covered by the local disposable suite, not a
new hosted worker-login test. No production role memberships were changed.

Postflight confirmed both functions are security definers with an empty search
path. Only `ingestion_worker` among worker/browser/service roles can execute the
CSV entry point; none can execute the internal writer. All test users/profiles and
source rows rolled back. Baseline remains eight runs, eight publications, seven
organisations and the same two ACNC source registrations; scheduling remains off.
Identity sequences may have advanced during rollback-only verification.

P12 deployment and hosted database verification are complete. Real-provider CSV
qualification remains pending receipt of a provider export/path/URL and its reuse
approval or licence evidence. No real CSV source has been enabled or published.

## Real-provider onboarding deferred — 18 September 2026

At the user's request, park real-provider CSV onboarding, including the planned NSW
associations export, until CSV information is received. **P12 remains complete,
deployed and verified.** Waiting for an external export is not unfinished importer
implementation and does not block P16 or the existing ACNC workflow.

Resume when a provider CSV/spreadsheet or download URL is available together with
its access/reuse approval or licence evidence. Then qualify the source, prepare the
manifest and mappings, validate and stage the file, and complete explicit operator
review before publication. Provider-specific mapping work may be needed.

The importer stays deployed and idle; the synthetic fixtures remain for regression
testing. No source activation, rollback, public data or schedule changes are needed.
Coverage from future CSV exports is deferred. Next engineering work is P16's
fixture-based exact-ABN adapter; ACNC schedule activation separately awaits the
operator's cadence decision.
