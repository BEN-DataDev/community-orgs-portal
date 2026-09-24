# ACNC qualification and private staging

For the current P09 storage contract and raw-retention implementation, see
[private ingestion storage](private-ingestion-storage.md). The historical notes below
describe earlier increments; P09 retention controls are recorded as complete and
deployed in the [deployment record](private-ingestion-storage.md#deployment-record).

Implemented: 16 September 2026. All four ingestion migrations are now applied
to Supabase project `gqltsfijginclwszrcfj`. Historical test notes below describe
earlier isolated verification. See the implementation plan’s development activation
section for the current deployment and verification status.

## Live source validation

Retrieved current dataset metadata and two bounded CKAN pages for postcode `2730`.
The original resource ID remains active. The first page returned five of six rows;
the second returned the remaining row. All six passed normalisation and envelope
validation with no quarantined records. Metadata declares **Creative Commons
Attribution 3.0 Australia**. See the [dataset metadata endpoint](https://data.gov.au/data/api/3/action/package_show?id=acnc-register)
and [register resource](https://data.gov.au/data/en/dataset/acnc-register/resource/eb1e6be4-5b13-4feb-b28e-388bf7c26f93).

[acnc-source-validation.json](acnc-source-validation.json) records the exact check
time, resource modification dates, licence, field types, query scope and page hashes.
Raw live records are not committed. Temporary responses/envelope are in `/tmp` for
this session; retained repository fixtures remain synthetic. Live data was used only
in the disposable database test, with no publication.

This validates one postcode sample, not national completeness, source-ID stability
across releases, current charity status for every record, or a repeatable snapshot
of the whole register. Use the complete-snapshot guard before any future reconciliation.

## Database foundation

[Migration](../supabase/migrations/20260916020403_private_ingestion_staging.sql) creates:

- `ingestion.sources`: registered resource/metadata; disabled by default.
- `ingestion.ingestion_runs`: immutable run key, envelope, completion and timestamps.
- `ingestion.source_records`: identity scoped to source, resource and native record ID.
- `ingestion.source_record_versions`: parser-versioned, database-hashed payloads.
- `ingestion.run_records`: observations linking each run to its record versions.
- `ingestion.field_assertions`: typed values associated with a source version.

The `ingestion` schema is private and must not be added to PostgREST exposed schemas.
All its tables have RLS enabled without browser-role policies. Public, anonymous,
authenticated and service-role access is explicitly revoked. A non-login,
non-superuser, non-bypass-RLS `ingestion_worker` role can execute only the staging
function; it has no direct table-write grants. An operational worker login and role
membership must be provisioned separately, using a dedicated credential.

`ingestion.stage_acnc(jsonb)` is a fixed-search-path security-definer function.
It requires an enabled source, validates envelope/record scope and assertions,
rejects changed content under an existing run key, and writes transactionally.
Unchanged versions are reused across observations. A failed assertion rolls back
the entire call, including run and version rows.

The function does not publish, create portal organisations, grant ownership or
interpret missing records as closed organisations. Complete, partial and failed
runs can all be stored as evidence. Completion does not confer publication approval.

## Approved validation-resolution extension

The current staging contract retains quarantine and error evidence but exposes only
accepted record versions through Import review. The approved
[P34a cross-source validation model](staged-validation-resolution.md) closes that
gap for every staged source and every failed field/record.

P34a keeps the original envelope and completion state immutable. It adds structured
issues, revision-fenced operator resolutions, authoritative server validation and
separately versioned derived runs. A correction never changes a partial run to
complete, and scope/schema/licence/acquisition failures cannot be manually
overridden. Publication remains behind the existing complete-run, identity,
selected-field approval and suppression gates.

Raw evidence is currently stored privately as JSONB, including the run envelope.
Before larger scheduled imports, add retention/removal operations covering both
copies and consider private object storage. The follow-up review migration adds review queues and candidate suggestions. The third migration adds mapped-field protection
and comparisons; the fourth migration adds selected-field publication. Withdrawal automation remains outstanding.

## Stage a validated envelope

From `tools/ingestion/python`:

```bash
python3 -m unittest discover -s tests -v
python3 -m ingestion.staging_sql --input examples/acnc-normalised.json --output /tmp/acnc-stage.sql
```

The second command validates raw hashes and record scope, then writes a transaction
calling the private function as `ingestion_worker`. Values are hex-encoded so source
text cannot become SQL or psql commands. It does not connect to any database.

On an explicitly chosen **development** database:

1. Apply the staging migration as the database administrator.
2. Register the source/resource in `ingestion.sources` with its reviewed metadata
   and `enabled = true`. The migration deliberately seeds no approved sources.
3. Apply the generated SQL with `psql -v ON_ERROR_STOP=1 -f /tmp/acnc-stage.sql`
   using a connection authorised to assume `ingestion_worker`.

Never point this procedure at an unspecified default database. Production rollout
requires checking migration state and provisioning the dedicated worker identity.

## Verification performed

- **17 Python tests pass**: original extraction tests plus staging validation,
  raw-hash tampering, conflicting metadata and duplicate assertions.
- [SQL regression](../supabase/tests/ingestion_staging.sql) passes: private grants,
  RLS enabled, idempotent runs, immutable run keys, version reuse, disabled/unknown
  source rejection and transactional rejection of malformed assertions.
- The six live sample records were staged twice: **1 run, 6 records, 6 versions**.
- Test database was disposable and isolated from the network. No existing database
  or portal table was changed.

The SQL tests require `anon` and `authenticated` roles, which exist in Supabase;
these were created only in the disposable test container for verification. Tests
use rollback-only synthetic fixtures. PostgreSQL 16 compatibility was exercised;
the hosted deployment and complete migration chain were not tested here.

## Next step

Build source/run administration and matching/change previews over staging. Before
deploying a live worker, add bounded HTTP transport, operator authorization and
source enablement workflow. Before publication, add revisions, manual field
protection, suppression/removal and reviewed publication transactions.

## Operator review

Apply `20260916020406_ingestion_review.sql` after the staging migration on a chosen
development database. The existing `community_orgs` API schema exposes three
narrow functions; **do not expose the private `ingestion` schema**. The page uses
the signed-in user's session, not a service key. Regenerate database types after
deployment; the three function signatures have been added locally in advance.

A database administrator appoints an existing, non-anonymous account:

```sql
insert into ingestion.operators(user_id) values ('<existing-auth-user-uuid>');
-- Revoke immediately with:
-- delete from ingestion.operators where user_id = '<existing-auth-user-uuid>';
```

Organisation admin/owner membership does not grant this capability. Operators
have access to raw import evidence and matching organisation details across the
portal, including non-public organisations. Appoint only accounts responsible for
this platform-wide work. Enrolled MFA requires an AAL2 session; missing assurance
claims fail closed. The navigation shows **Ingestion work queues** to eligible operators.

At `/admin/ingestion/identity`, choose a run and record, inspect source fields/provenance,
compare candidates and save a reasoned link/create/defer/reject proposal. Exact
ABN and name matches are labelled suggestions, including shared-ABN branches.
Records from incomplete runs remain available for investigation. Decisions attach
to an immutable source version, so unchanged versions retain their decision across
runs; changed versions need a fresh review. No organisation is created, linked,
updated, published or assigned an owner by saving a proposal.

`ingestion.reviews` stores the latest decision/revision; `ingestion.review_events`
retains each saved revision. A stale revision fails instead of overwriting a newer
decision. Direct browser table access remains revoked. History inspection currently
requires database administration; no history or operator-management UI is included.

Verification commands:

```bash
node scripts/test-ingestion-review.mjs
npm run check
npm run build
# On a disposable development database after both migrations:
psql -v ON_ERROR_STOP=1 -f supabase/tests/ingestion_review.sql
```

Review SQL tests cover unauthorised/anonymous/revoked operators, shared ABNs,
run membership, decision validation, stale revisions, event history and no
organisation creation. Additional isolated auth-claim tests covered enrolled MFA
with missing/AAL1/AAL2 assurance. Svelte checks and route tests pass; the production
build succeeds with sourcemap/annotation and optional Sharp packaging warnings.
Browser interaction and a full Supabase deployment still need verification.

## Field previews and protection — 16 September 2026

Apply `20260916020408_ingestion_field_preview.sql` after the review migration.
**Compare fields** on a candidate opens a current/source comparison. A saved link
is the default comparison target; an explicit new-organisation preview clears it.
Comparing does not change the saved match or approve any field.

The first mapping covers `organisations.entity_name`, `legal_details.abn` and
`contact_info.website`. Dates, administrative addresses, aliases and other source
assertions remain **unmapped** evidence until their semantics are agreed. ABNs
are not verified by this comparison. Missing/null assertions never propose a
clear. Non-string/blank values are invalid; multiple child rows are ambiguous.

Private `ingestion.field_state` records a revision and protection marker per
organisation/table/field. The migration protects existing non-null mapped values.
Database triggers track subsequent changes through existing forms or direct
writes, including null clears and child-row deletion; no-op updates do not bump
revisions. New non-null values are protected too. Organisation reassignment of
these rows requires a reviewed migration. Direct client access to protection
state is revoked; there is no browser-controlled bypass or unlock operation.

Previews classify fields as **new, unchanged, changed, conflict, missing,
unmapped, invalid or ambiguous**. A differing protected field is a conflict even
if its current value is null or its child row was deleted. These markers prevent
such differences being presented as ready-to-apply updates; they do not prohibit
ordinary authorised human edits.

This increment supplied the protection/preview foundation. The publication
increment below adds immutable selected-field snapshots and enforcement. Previews
remain live reads; record-level reviews alone do not authorise publication. There
is no automatic unlock.

Validation: `supabase/tests/ingestion_field_preview.sql` exercises access denial,
new/missing/unmapped values, unchanged fields, protected edits/clears/deletions,
no-op revisions and multiple target rows. Run it with `psql -v ON_ERROR_STOP=1`
on a disposable database after all three migrations. Route tests additionally
check saved-link/default-new targets and preview failures. Local SQL testing used
PostgreSQL 16 with minimal auth/portal fixtures, not a full hosted migration chain.

## Selected-field approval and publication — 16 September 2026

Apply `20260916020409_ingestion_publication.sql` after the field-preview migration.
The operator workflow is:

1. Save a **link** or **create** review with an identity-check note.
2. Compare the saved target and select eligible fields. New organisations require
   the name field. Missing, protected, invalid, ambiguous and unmapped values are
   not eligible. ABNs must have 11 digits; websites must use HTTP(S) and fit the
   portal column. ABN format checking does not establish registry validity.
3. Save the field approval. The server compares each displayed snapshot with a
   fresh preview, including values, row count, protection and revision. A changed
   review target/revision or stale field requires another review.
4. Inspect the saved target and before/after values, then choose **Publish these
   approved fields**. Only selected fields are applied.

New organisations are explicitly **public**. Linked organisations retain their
existing visibility, including private visibility. A private `creation_targets`
marker lets the existing owner-grant trigger recognise an imported creation. No
ownership/role grants are made for imports; normal portal creation retains its
owner grant. The marker is not a client-controlled setting. Complete runs from enabled sources are required at approval and publication.
The worker's `publication_eligible: false` envelope remains unchanged: extraction
never confers permission to publish; the separate operator approval does.

Private `change_sets` stores immutable approvals; `publications` records the actor,
time, resulting organisation and applied snapshots; `source_links` binds each
resource-scoped native record to one portal organisation. All are RLS-enabled with
no direct browser/service-role table grants. The three API functions require the
same operator/MFA checks as review. The UI shows the latest 20 approvals per version.

Publication locks the three mapped portal tables in a fixed order, rechecks the
review, source enablement, field snapshots, protection and source link, and applies
all selected fields in one transaction. Any failure rolls back every write. These
coarse locks intentionally favour correctness for the small pilot; they briefly
block portal writes and must be replaced/measured before high-volume publication.
They also cover missing child rows, preventing an insert from racing the preview.

Retrying a published change-set ID returns its recorded organisation without
writing again, even after a later human correction. Another create approval for
an already linked source record is rejected. Different native source identities
still require human duplicate checks; shared ABNs/names never automatically merge.
Imported values remain protected by the existing triggers. This conservative first
version allows filling unprotected gaps and creating organisations, but does not
allow unattended refreshes or conflict overrides. It does not unlock human values.

The publication UI records history for operators; public source-attribution screens,
withdrawal/suppression, conflict resolution, guarded rollback and bulk scheduling
remain separate work. Regenerate API types after deployment; local signatures have
been added in advance. No hosted migration or live publication was performed.

### Publication verification

`supabase/tests/ingestion_publication.sql` uses rollback-only synthetic fixtures.
It covers operator denial, protected fields, wrong-target approvals, a failure on
the second field rolling back the first, visibility preservation, selected-only
writes, replay after human corrections, stale field/review revisions, source
pause/incomplete runs, public creation, duplicate source-identity prevention and preservation of normal
owner grants while imported creation grants none.
Run it as postgres on a disposable database after all four migrations. Tests here
used PostgreSQL 16 with minimal auth/portal fixtures; this does not verify the
complete hosted schema, browser interaction or deployment.

Svelte checks, targeted ESLint/format checks, route/session tests and production
build passed. Build output retains the existing annotation/optional Sharp warnings.

## Deployed synthetic sample

Run `1` (`offline-acnc-sample-v1`) now contains two synthetic records for the Admin
→ Import review task. Source/resource metadata marks the sample as synthetic.
A deployed-schema integration test exercised selected-field publication and human
edit protection in a transaction that was rolled back; no public sample organisations
or approvals remain. The sample is ready for inspection in the signed-in UI.

To repeat the database verification using an administrative connection, set
`test.ingestion_operator` to an existing authorised operator UUID and execute
`supabase/tests/ingestion_deployed_workflow.sql`. It requires the untouched fixture
and intentionally stops if its first version has already been reviewed. It uses
transaction-local authenticated claims, not an actual browser session. Publication
writes are rolled back, though database sequence values may advance.

## Public attribution and withdrawal

Migration `20260916034216_attribution_and_suppression.sql` is deployed. The organisation
overview calls `organisation_source_attribution` after its access checks. Responses
contain only source identity, reviewed display/link/licence metadata, observed and
published dates, field names and an edited-since-import flag. No raw values, actor
IDs or private review/suppression reasons are exposed. Hidden organisations return
no public attribution to unauthorised callers. Organisation overview responses use
`private, no-store` caching; existing externally cached copies are not purged.

Populate these **reviewed public fields** in `ingestion.sources.metadata` when
qualifying a real source (the private raw metadata can retain additional keys):

| Key                  | Purpose                           |
| -------------------- | --------------------------------- |
| `public_title`       | Public source/publisher label     |
| `public_url`         | HTTP(S) dataset/register page     |
| `public_licence`     | Reviewed licence/attribution text |
| `public_licence_url` | HTTP(S) licence page              |

Missing titles fall back to the source ID; missing licence/link fields are omitted.
Synthetic sources are always labelled **Synthetic test data**. Public URL rendering
rejects non-HTTP(S) schemes and embedded credentials. Dates describe retrieval and
publication, never independent confirmation. Revision changes distinguish manual
corrections even if a user eventually restores the same text.

The **Withdrawal and suppression** panel operates on the selected source record's
actual linked organisation, not a candidate currently being compared. It shows the
linked target and current ABN/website before field removal. A reason and explicit
confirmation are required. `suppress_ingestion_content` repeats the capability check,
locks the portal tables in publication order, validates the target/snapshot and
records suppression before removing the value or changing `is_public` to false.
Ambiguous child rows and stale field previews are rejected atomically. For an
unpublished record, suppression simply blocks future publication of that content.

`ingestion.suppressions` is private, RLS-enabled and client writes are revoked.
It retains the first reason, operator and timestamp per native-record/field; repeated
requests do not erase that evidence. Field suppression covers every version of that
source identity and imports targeting the linked organisation. Publication/approval
gates reject suppressed content, and target-table triggers reject attempts to
restore a suppressed field or make a withdrawn organisation public. There is no
client-controlled bypass, and no restore button. Suppression under one source ID
does not automatically discover the same entity under a different resource/native
ID when it is proposed as a different organisation.

Explicit ABN/website removal clears the current value even if manually corrected;
operators must review the displayed value. Withdrawing an entire record hides the
whole linked organisation, including independently entered content. Required entity
names are retained privately rather than nulled. Private staging evidence and audit
history are retained: this is withdrawal from publication, not complete erasure.

Regression: `supabase/tests/attribution_and_suppression.sql` requires an existing
operator UUID in `test.ingestion_operator`. It creates synthetic records and rolls
back every change. It passed against the actual deployed schema. The earlier staged
sample remains untouched and can be used for a signed-in browser walkthrough.

## Retained suppression redaction — 20 September 2026

Apply `20260920020000_retained_suppression_redaction.sql` after complete-snapshot
reconciliation. Suppression remains the operator-facing withdrawal/correction
decision; this increment adds targeted private retained-copy cleanup behind that
decision.

When a field or record is suppressed, the database now redacts matching retained
source assertions/raw keys from `source_record_versions`, run envelopes, acquisition
checkpoints and private change-set/publication snapshots. Source identity, content
hashes, links, publication records and suppression reasons remain private and
auditable. `retained_evidence_redaction_events` records the affected source identity,
field, operator, reason and copy counts. Browser roles and the ingestion worker have
no direct access to the event table or redaction functions.

The staging and checkpoint worker entry points reapply redaction for any already
suppressed source identity, so a later acquisition or replay cannot rehydrate the
withdrawn value. Offline reprocessing from a redacted parent fails because the
retained parent evidence no longer matches the replay envelope; acquire fresh source
evidence and re-review instead. Whole-record withdrawal redacts retained assertions
and raw evidence for that source identity while keeping the private suppression
decision and source linkage.

Validation: `supabase/tests/retained_suppression_redaction.sql` covers source
versions, run envelopes, checkpoints, approval/publication snapshots, redaction
events, future staging and whole-record withdrawal. The generated ingestion SQL
suite, including reprocessing tests updated for the new replay block, passed against
a disposable PostgreSQL 16 container.
