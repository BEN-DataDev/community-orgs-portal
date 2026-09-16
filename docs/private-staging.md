# ACNC qualification and private staging

Implemented: 16 September 2026. Migration tested in an isolated PostgreSQL 16
container, not applied to the hosted portal.

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

[Migration](../supabase/migrations/20260916010000_private_ingestion_staging.sql) creates:

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

Raw evidence is currently stored privately as JSONB, including the run envelope.
Before larger scheduled imports, add retention/removal operations covering both
copies and consider private object storage. The follow-up review migration adds review queues and candidate suggestions; field
locks, publication and withdrawal automation remain outstanding.

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

Apply `20260916020000_ingestion_review.sql` after the staging migration on a chosen
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
claims fail closed. The navigation shows **Import review** to eligible operators.

At `/admin/ingestion`, choose a run and record, inspect source fields/provenance,
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
