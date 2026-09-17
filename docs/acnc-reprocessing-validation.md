# ACNC retained-pilot replay validation

17 September 2026. **F05 release gate complete following operator verification.**
V2 remains retained as partial run 7; v3 is complete run 8 with six accepted
records and zero quarantine. The operator confirmed approval/publication and all
post-publication checks, including hosted signed-out pages, attribution/dates,
coverage, exclusions/suppression and duplicates. This records user confirmation,
not a new automated test run or newly measured publication totals.

[Website normalisation v3](acnc-website-normalisation.md) records the current
migration, replay and closure status. Acquisition job controls and scheduling
are now the next implementation work; they have not been enabled by this update.

## Historical v2 validation

The remaining results describe the earlier v2 replay and its staging-time state,
before the v3 qualification and subsequent operator approval/publication.

The offline replay reads the complete retained envelope from run 6 and uses
`acnc-ckan-v2` / `acnc-register-fields-v2`. Its new run key is
`acnc-reprocess-run-6-v2`. The observation remains
`2026-09-16T04:47:41.708096+00:00`; processing time is recorded separately.
Raw records, hashes, original page hashes, resource identity, source URLs and
qualification metadata are preserved. Private artifacts stay outside the repository.

| Retained-pilot result                      | Count |
| ------------------------------------------ | ----: |
| Original records examined                  |     6 |
| Accepted by parser v2                      |     5 |
| Quarantined records                        |     1 |
| Supplied, valid organisation-column values |   135 |
| Absent organisation-column values          |   278 |
| Invalid organisation-column values         |     1 |
| Unmapped organisation columns              |     0 |

The column counts total 414 (69 organisation columns × six records). `_id` is
explicitly technical and excluded. Valid values in a quarantined record are
counted as supplied, but the whole record remains unavailable for publication.
The [machine-readable coverage summary](acnc-reprocessing-coverage.json) contains
per-column counts and independent workflow results, without raw values or contacts.

The invalid value is a website without an HTTP(S) scheme. The existing parser
requires an absolute HTTP(S) URL. The replay neither invents a scheme nor drops the
website to make the run pass. It preserves the rejected record and records the
reason. The new run is **partial**, so even its five accepted records cannot be
approved or published. Qualifying a safe transformation requires a separately
versioned parser/mapping change and new replay; changing the retained evidence or
the completion flag is not a remedy.

## Verified behaviour

- Forty Python tests pass, including preservation, deterministic replay, tampered
  hashes/identity rejection, quarantine and source-versus-workflow coverage states.
- The isolated PostgreSQL harness applies the real F02–F05 migrations. Existing
  staging, review, publication, register constraints and anonymous-access suites
  pass. All 62 review units round-trip through publication, including false flags,
  long strings, structured addresses and reporting calendar values.
- New replay SQL tests preserve parent versions and source links, reject changed
  observations/raw evidence/identity/page hashes/missing rows, reject old approvals,
  retain manual edits and withdrawals, and create no duplicate organisations or
  child projections on retry. Anonymous roles cannot access replay evidence.
- The actual retained six-record envelope passes the disposable-database pilot
  suite. The existing link for ABN **75349327058** is reproduced for testing using
  the review API. Replay retains it and displays previously published values.
  A partial run cannot gain field approval. All test writes roll back.
- Real public page loaders, Svelte server rendering and Chromium checks pass for
  all 62 units across five pages, including attribution, disagreement, suppression,
  withdrawal and retrieval errors. These use anonymous exports from the isolated
  database; they are not hosted browser verification.
- Review route tests confirm the existing linked organisation is the default
  preview target and an explicit target still takes precedence. Svelte checking
  reports zero errors and zero warnings.

Approval and publication flags in the operator coverage RPC describe saved
history for that run/version. They do not assert that a saved approval remains
usable or that a historical publication is still visible. Suppression is reported
independently. Quarantined rows have no new version or workflow state; their flags
remain unknown in the column report. Missing values are not implementation success.

## Live execution

After explicit user approval, all four migrations were applied to Supabase and
the private replay was staged as **run 7**, linked to original run 6. It contains
five source versions and one quarantined record, with zero new approvals or
publications. Its staging time is `2026-09-16T23:05:55.357757+00:00`.

Applied migrations, in order (Supabase MCP assigned the deployment timestamps):

1. [F02 register storage](../supabase/migrations/20260916070000_acnc_register_details.sql) — deployed `20260916230347`
2. [F03 complete publication](../supabase/migrations/20260916080000_complete_field_publication.sql) — deployed `20260916230353`
3. [F04 public facts](../supabase/migrations/20260916090000_public_register_facts.sql) — deployed `20260916230358`
4. [F05 replay lineage and reporting](../supabase/migrations/20260917010000_acnc_reprocessing.sql) — deployed `20260916230402`

Live before/after checks confirm that run 6's envelope hash, all six original
version hashes and both existing source links are unchanged. Organisation,
approval and publication counts remain two each. There is exactly one replay run,
with five versions for five existing source identities. The source's existing
enabled state was unchanged.

Hosted operator checks confirm the existing link for ABN 75349327058, no inherited
review, and a complete 62-unit preview. Hosted anonymous-role checks return only
the two previously published facts and zero register projections. Private staging
tables and the operator coverage report deny anonymous access. Hosted browser
verification was pending at this stage; database checks alone did not establish a
UI deployment. The operator subsequently confirmed verification for v3 above.

The initial `SET LOCAL ROLE ingestion_worker` failed. Inspection confirmed the
connection is the function owner (`postgres`) with existing EXECUTE permission;
the function is SECURITY DEFINER and executes as that same owner for worker calls.
The approved replay then succeeded through the unchanged validating function,
without granting roles or changing permissions. Automatic approval review declined
an optional second live invocation over duplicate-write concerns. Local retry tests
pass, and read-only live checks confirm no duplicate run, identity or publication.

At this stage, the invalid URL required qualified mapping followed by fresh review
and separate publication. V3 subsequently resolved that blocker; the operator
confirmation above closes the release gate.

## Reproduction

From `tools/ingestion/python`, with a private export of run 6's `envelope`:

```sh
python3 -m ingestion.reprocess_acnc \
  --input /private/retained-envelope.json --parent-run 6 \
  --run-key acnc-reprocess-run-6-v2 \
  --processed-at '<actual processing time in ISO 8601 with timezone>' \
  --output-dir /private/new-replay-directory
python3 -m unittest discover -s tests
```

The output directory must be new. It is mode 0700, with 0600 envelope, coverage
and SQL artifacts. The CLI performs no network or database operations. The
separate `ingestion.reprocess_acnc.coverage(envelope, workflow)` function combines
an operator `ingestion_reprocessing_report` RPC response with per-column source
states and rejects a mismatched run key.

Generate the synthetic SQL suites with `scripts/build-ingestion-test-sql.py` and
apply only to an empty disposable database. For retained-pilot testing, start a
transaction and supply `test.pilot_parent`, `test.pilot_replay` and
`test.pilot_source` settings, then run `supabase/tests/acnc_retained_pilot.sql` in
that same disposable database. It rolls back every test write. Never run either
test setup against the live database.
