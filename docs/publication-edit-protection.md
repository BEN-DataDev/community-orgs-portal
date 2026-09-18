# Publication and edit protection (P10)

Complete for the current mapped import scope, 18 September 2026. This record
consolidates the existing publication, complete-field and suppression increments;
no new application behaviour or database migration was required for closure.
ACNC has 62 review units covering 69 source columns. CSV currently publishes only
name, ABN and website through the same controls; unmapped assertions remain private.

## Acceptance and evidence

| P10 requirement | Implemented behaviour | Current regression evidence |
| --- | --- | --- |
| Explicit publication state and visibility | Staging and review are private. Saving an immutable approval has no public effect. Only an explicit transactional publication creates public imported organisations. Existing organisation visibility is preserved; hidden source projections cannot be restored by import. | `ingestion_staging.sql`, `ingestion_publication.sql`, `ingestion_complete_fields.sql`, `public_register_facts.sql` |
| Revision checks | Approval captures the review revision and complete selected-field snapshots. Publication rechecks source/mapping tokens, target values, revisions, row counts, protection and visibility. A changed review or target requires fresh approval. | `ingestion_publication.sql`, `ingestion_complete_fields.sql` |
| Manual field ownership | Private `field_state` tracks revisions, protection, actor and time. Existing mapped values are backfilled as protected. Manual changes, clears and child deletions protect fields; imports report conflicts. Successful publication releases protection only for selected fields it wrote. | `ingestion_field_preview.sql`, `ingestion_complete_fields.sql`, `acnc_reprocessing.sql` |
| Publication events | Private `change_sets` hold approvals; `publications` records the approval ID, organisation, publishing actor/time and selected before/after snapshots. Writes and bookkeeping are atomic. Repeating a published approval does not duplicate writes or overwrite later human corrections. | `ingestion_publication.sql`, `ingestion_complete_fields.sql` |
| Suppression rules | A reasoned suppression persists across source versions, clears the selected fact across projections and blocks direct restoration and import replay. Required-name suppression withdraws the organisation. Anonymous fact/attribution projections exclude suppressed or withdrawn content. | `ingestion_complete_fields.sql`, `public_register_facts.sql`, `acnc_reprocessing.sql` |
| Preserve access and ownership | A private creation marker makes imported creation skip the owner-grant trigger. Normal portal creation still grants its creator ownership. Operator scope and conditional MFA remain enforced. | `ingestion_publication.sql`, `ingestion_complete_fields.sql`, `operator_access.sql`, access/role regression suites |

The SQL suites live in [supabase/tests](../supabase/tests). Manual field ownership
means precedence over source writes, not a new per-field user permission system.
These import revision checks do not establish optimistic concurrency for every
ordinary portal edit form.

## Lifecycle contract

State is represented by durable records rather than a second status column:

1. Source versions and assertions are staged privately; no portal organisation is
   created and no ownership is granted by staging or review.
2. A saved link/create review identifies the intended target. Defer/reject cannot
   authorise publication.
3. A selected-field change set records approval. It remains private and can become
   stale; historical approval alone does not mean publication is currently allowed.
4. `publish_ingestion_fields` checks operator access, complete enabled source,
   identity link, suppression and fresh snapshots, then writes fields and the
   publication event in one transaction. New imported organisations are explicitly
   public; linking does not change an existing organisation's visibility.
5. Current public visibility depends on organisation/projection visibility and
   suppression. A historical publication event does not imply current visibility.

Missing source assertions never clear portal values. Manual protection is not an
operator override switch. Withdrawal can deliberately remove a human-corrected
value after confirmation; it is distinct from an ordinary source refresh.

## Verification on 18 September 2026

The expanded [disposable database runner](../scripts/test-operator-access-db.py)
passed with **36 unmodified portal/access/ingestion migrations**, **15 SQL suites**,
the approved CSV integration and concurrent owner-revocation checks on PostGIS 17.
Its database has no network or host mounts and is removed at the end. Auth users,
factors and JWT helpers are emulated; the real role, MFA and RLS functions run.
The complete-field suite now seeds a verified MFA factor when using this full
schema, while retaining compatibility with the older isolated harness's test claim.

The review route tests and source-attribution validation also passed:

```sh
python3 scripts/test-operator-access-db.py
node scripts/test-ingestion-review.mjs
node scripts/test-source-attribution.mjs
```

Read-only hosted checks against project `gqltsfijginclwszrcfj` confirmed:

- Migration history contains field preview, publication, attribution/suppression,
  complete-field publication, public facts, reprocessing and website normalisation,
  plus the later access, retention and CSV migrations.
- All four field-protection triggers, all four suppression/withdrawal triggers
  and the ordinary owner-grant trigger are enabled; 62 mappings are installed.
- `field_state`, `change_sets`, `publications`, `suppressions` and
  `creation_targets` have RLS enabled, deny anonymous SELECT and deny authenticated
  INSERT/UPDATE/DELETE.

Hosted behaviour/browser evidence is reused from the recorded
[F05 operator verification](acnc-reprocessing-validation.md) and
[P12 hosted checks](approved-csv-import.md#hosted-deployment-and-verification--18-september-2026).
Today's hosted checks establish migration/catalog state, not a new end-to-end
publication or browser test. No hosted data, grants, source settings or schedules
were changed for P10 closure. No application code changed, so an application
build or redeployment was not needed for this increment.

## Deployment and forward repair

The relevant implementation is in these existing migrations, in order:

- `20260916020408_ingestion_field_preview.sql`
- `20260916020409_ingestion_publication.sql`
- `20260916034216_attribution_and_suppression.sql`
- `20260916070000_acnc_register_details.sql`
- `20260916080000_complete_field_publication.sql`
- `20260916090000_public_register_facts.sql`
- `20260917010000_acnc_reprocessing.sql`
- `20260917020000_acnc_website_normalisation.sql`

Hosted F02–F05 timestamps differ from local filenames; the exact deployed mapping
is recorded in [F05 deployment evidence](acnc-reprocessing-validation.md#live-execution).
Website normalisation is recorded as hosted `20260916232821`.

For a failed or suspect publication:

1. Check the saved approval and publication history first. Failed transactions
   leave no partial publication. After an uncertain response, retry the same
   approval through the RPC; it is idempotent, subject to current access and
   suppression checks. Do not create another organisation to resolve uncertainty.
2. If snapshots changed, reload the review and inspect conflicts. Obtain a fresh
   selected-field approval only for eligible fields; do not clear manual protection
   or rewrite old approvals to force publication.
3. If published content must be removed, use the existing reasoned field
   suppression or whole-record withdrawal workflow. Pausing the source prevents
   further publication but does not remove already public content.
4. For a schema defect, pause the affected source, retain audit and suppression
   records, and reproduce the issue in the disposable runner. Apply a new reviewed
   forward migration and rerun the acceptance suites before resuming. Do not drop
   protection tables, disable triggers or replay old schema migrations over current
   data as a rollback strategy. Preserve organisation UUIDs and relationships.

Automatic reversal of already committed imported values is **P29**, not this
transaction-failure recovery. Unsuppression and conflict overrides remain separate
work. Suppression does not erase private evidence, purge external caches or find
duplicates under unrelated source identities. The current table-level publication
locks remain appropriate only for the bounded pilot.
