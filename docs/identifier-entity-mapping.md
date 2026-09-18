# Identifier and entity mapping (P11)

Version 1.0, 18 September 2026. P11 is complete as a **definition and migration
contract**. [P14 identity schema, matching and reviewed legacy backfill are now deployed](deterministic-matching.md#hosted-completion--18-september-2026).
P16 supplies exact-ABN evidence.
Branch/service publication needs the corresponding schema, review and publication
changes before those CSV holds can be released.

## Existing behavior and evidence

The [baseline schema](../supabase/migrations/20260101000000_baseline_community_orgs_schema.sql)
uses `organisations.org_id` UUIDs. `legal_details` has text ABN, ACN and incorporation
number columns, but no incorporation jurisdiction or verification evidence. Its
`entity_type` is a legal description, not a legal-entity/branch/service discriminator.
The ABN index is non-unique. Legal child rows are keyed by `legal_id`; do not assume
one row per organisation when planning a backfill.

`programs_services` already has `program_id` and an organisation link. Existing
`relationships` has free-text type and partner fields; these are not evidence of
a verified legal parent. Neither structure establishes a canonical entity model.

[Staging](../supabase/migrations/20260916020403_private_ingestion_staging.sql)
uniquely identifies a source record by `(source_id, resource_id, native_id)`.
[Publication](../supabase/migrations/20260916020409_ingestion_publication.sql)
permits one organisation link per source record and many source records per
organisation. The [review queue](../supabase/migrations/20260916020406_ingestion_review.sql)
suggests exact ABN/name candidates; it does not verify identifiers or merge records.

The [qualified ACNC sample](source-sample-qualification.md#schema-and-identity)
has resource-scoped CKAN `_id` values and text ABNs. `_id` is not a cross-release
identifier. The [CSV importer](../tools/ingestion/python/ingestion/approved_csv.py)
preserves `entity_kind`, incorporation jurisdiction/number and other metadata as
private `csv_*` assertions. Only name, ABN and website currently publish. It accepts
NSW incorporation pairs and checks ABN shape only; branches and services are held.
The [fixture](../tools/ingestion/python/tests/fixtures/csv-pilot-v1/organisations.csv)
contains a shared ABN, no-ABN group, service and leading-zero incorporation number.
Its all-zero ABN is synthetic and must never become verified identity evidence.

## Entity destinations

These decisions implement the [P01 inclusion rules](pilot-inclusion-policy.md)
without requiring every eligible group to hold a registration.

| Reviewed kind | Target | Identity and relationship rule |
| --- | --- | --- |
| `legal_entity` | Existing or new `organisations.org_id` | Holds its own verified identifiers. A source label or ABN alone does not establish this classification. |
| `community_group` | Existing or new `organisations.org_id` | Independent community identity; identifiers are optional. Review any claimed legal registration before changing kind. |
| `branch` | Separate `organisations.org_id` | Local identity plus an evidenced link to its legal entity. A parent's ABN is a reference to the parent, not an identifier owned by the branch. |
| `service` | `programs_services.program_id` | Link to the delivering organisation via `org_id`; do not create another legal entity for the program name. |
| `unknown` | Existing organisation retained; new candidate deferred | Migration default when classification evidence is absent. Never infer legal status from the presence of an ABN. |

A branch with independent legal identity is classified as a legal entity; its
affiliation can remain a separate relationship. Auspicing, affiliation and service
delivery do not imply legal ownership. A trading name is an alias when evidence
shows it names the same entity; a similar name alone is insufficient. Addresses,
websites and names generate candidates, never unique keys.

For branches, define a typed `branch_of` link to a legal entity with evidence,
review actor/time and effective dates. Reject self-links, cycles and overlapping
current legal parents. Preserve other affiliations separately. A service may be
delivered by a branch or legal entity. Multiple deliverers require a reviewed
many-to-many extension; hold those imports until it exists, rather than selecting
an arbitrary provider. Do not duplicate services merely because their names or
delivery sites differ; assess source identity and actual program scope.

## Identifier contract

An identifier key is `(scheme, jurisdiction, normalized_value)`, with all three
components required for a matchable claim. Values remain text. Retain raw spelling,
normalizer version, source/version reference and observation time privately.

| Scheme | Jurisdiction | Normalization and use |
| --- | --- | --- |
| `abn` | `AU` | Trim outer whitespace and remove permitted display spaces; require 11 ASCII digits. Checksum validation precedes verification. Do not strip arbitrary letters/punctuation or convert through a number. |
| `acn` | `AU` | Preserve nine ASCII digits, including leading zeros; allow qualified display spaces. Implement scheme validation before enabling verification/matching. No ACN is inferred by slicing an ABN. |
| `incorporated_association` | `AU-NSW` initially | Preserve leading zeros and internal punctuation/case unless an approved registry-specific normalizer establishes equivalence. Map CSV `NSW` explicitly to `AU-NSW`. |
| Provider-native ID | Source and resource namespace | Keep in `source_records`, not as a nationally unique legal identifier. New resources require reviewed crosswalks, not automatic `_id` reuse. |

Other states require separately qualified jurisdiction/normalizer mappings. Missing
jurisdiction is unresolved evidence, not `AU`, NSW inferred from an address, or a
wildcard. Thus NSW `0000123`, VIC `0000123` and NSW `123` are distinct keys until
registry evidence establishes an equivalence. Malformed values are quarantined;
ambiguous but well-formed claims are held for review.

Keep these dimensions separate:

- **Validation:** unchecked, valid, invalid, with validator version. A checksum
  proves syntax only, not existence, ownership or current activity.
- **Verification:** unverified, verified, disputed, withdrawn, with evidence,
  verifier/actor and verification time. Record failed/unavailable lookup attempts
  separately; a timeout or absent access GUID does not prove invalidity.
- **Registry status:** source-native status and effective dates, independently of
  verification and the portal's visibility or operational closure.
- **Association:** the legal entity holding the identifier, or a reference to
  that holder from a branch/service. Never promote the latter to holder identity.

Verified means an authorised review has accepted qualified registry evidence that
binds the exact key to the legal entity. P16 defines response handling and evidence
freshness for ABN Lookup; it must not treat transport success as verification.
Retain verification history and explicit disputes. Cancelled registrations do not
free their identifier for reassignment or prove that all services have closed.

## Target storage and duplicate constraints

P14 migrations must implement these invariants transactionally, including concurrent
review/publication; UI checks alone are insufficient:

1. Add explicit organisation kind with `unknown` as the legacy default. Store
   classification evidence/revisions privately. Changing kind must revalidate
   identifier ownership and branch links and invalidate affected approvals.
2. Retain competing identifier assertions separately from canonical identity.
   Use an identifier-key table unique on `(scheme, jurisdiction, normalized_value)`
   and at most one accepted legal-entity holder per key. Multiple independent
   source assertions may support that holder without duplicating it. Only verified
   legal-entity claims enter this canonical association; disputed claims remain
   available for review without weakening uniqueness.
3. Retain the last accepted holder during a dispute or withdrawal as restricted
   history/reservation, subject to applicable retention/suppression policy. A
   deliberate audited correction may replace it; cancellation or failed refresh
   cannot silently transfer it. Conflicting owners block deterministic matching.
4. Enforce one current accepted ABN per legal entity. Multiple historical claims
   remain evidence, not simultaneously active matching keys. Other schemes need
   qualified cardinality rules before enforcing a one-per-entity constraint.
5. Do **not** add global uniqueness to `legal_details.abn` or incorporation number.
   Legacy display fields can contain unverified or shared values. They become
   reviewed projections, not the authority for matching. Never copy a parent's
   ABN into a new branch's own legal details.
6. Preserve source-record uniqueness and one target per source record. Extend
   source links to exactly one organisation **or** service foreign key, with an
   exclusive-target check; preserve existing organisation links unchanged. A
   composite source record that describes several entities requires an adapter
   with stable component IDs or a hold, not a multi-target identity shortcut.
7. Foreign keys preserve existing UUIDs; entity merges are a separate audited
   workflow. No unique name, postcode, website or shared contact constraint.

Identifier assertions, verification evidence, conflicts and mutation audit stay
private under the existing operator/MFA boundary. Organisation editors can propose
corrections but cannot mark themselves registry-verified; workers stage evidence
without assigning canonical holders. Public projections must respect visibility,
manual protection and suppression. Raw evidence is not exposed through a new API.

## Matching handoff to P14/P16

Check an existing source link first, but hold a material identity contradiction or
suspected native-ID reuse. Next consider an exact accepted, verified ABN belonging
to a legal entity, then a verified incorporation key including jurisdiction.
Different strong identifiers pointing at different entities always produce a hold;
precedence must not hide a contradiction. Branch/service scope blocks a legal-entity
merge even where the referenced ABN agrees. Unverified values and names only rank
candidates. No match still requires an explicit reviewed create decision.

Approvals must capture identity/classification/link revisions as well as field
revisions. Publication rechecks them and canonical uniqueness under database locks;
concurrent contenders cannot create two accepted holders. Replaying a source/version
or approved publication must reuse its target. Verification does not authorise
publication or override a manual correction/suppression.

## Migration path for existing records

No production census or backfill was performed for P11. The existing-record basis
here is the repository schema and recorded pilot evidence; actual row counts and
conflicts are a deployment gate, not assumed clean data.

1. **Inventory privately before migration.** Produce a read-only report keyed by
   `org_id`/`legal_id`: multiple legal rows, empty/malformed identifiers, normalized
   ABN collisions, unscoped incorporation numbers, conflicting source links and
   possible service/branch rows. Record organisation, role, relationship, service,
   publication and suppression counts. Review actual source headers alongside it.
2. **Expand without rekeying.** Add private assertion/canonical-key/classification
   structures and typed links. Keep all UUIDs, child IDs, roles, URLs, existing
   source links and audit references. Default legacy kinds to `unknown`. Apply
   private grants/RLS and audited RPCs before enabling any writes.
3. **Idempotent evidence backfill.** Copy legacy values as unverified claims with
   stable migration keys based on original row ID, field and value hash. Record
   their origin as legacy data, not invented registry observations. Leave missing
   incorporation jurisdictions unresolved; report duplicate child rows instead
   of selecting one. Do not alter public projections or mark values verified.
4. **Review and reconcile.** Classify evidenced entities; confirm jurisdiction,
   holder and branch/deliverer relationships. Shared ABNs may be a branch reference,
   erroneous value or genuine duplicate; each needs a recorded decision. Preserve
   existing IDs even for suspected duplicates. Legacy services represented as
   organisations remain `unknown` until a separate reviewed conversion preserves
   inbound links, permissions and history; do not delete or auto-convert them.
5. **Enable canonical constraints and writers together.** Populate accepted keys
   only after collision review. Route identifier edits, verification and publication
   through revision-aware transactions; manual changes dispute/invalidate matching
   evidence until reviewed. Prevent direct writes from bypassing these rules.
   Regenerate application types and extend review/publication for service targets
   before releasing service/branch holds. Keep ambiguous claims out of matching.
6. **Validate then release.** Run the acceptance cases below in a disposable full
   schema, including concurrent conflicting claims, denied role access and replay.
   Compare pre/post UUIDs, inbound references, permissions and public projections.
   Hosted rollout requires its own migration and read-only integrity verification.

On failure, disable the new matching path and retain staged evidence for manual
review. Additive schema can remain while old publication operates within its
existing scope. After canonical decisions exist, prefer an audited forward repair:
restore a prior holder/link only after checking intervening revisions and invalidate
stale approvals. Never roll back by dropping identity history, renumbering UUIDs,
clearing human corrections or bypassing suppression. A destructive merge is outside
this migration and requires its own recovery design.

## Acceptance scenarios

These are implementation requirements, not claims of new passing runtime tests.

| Case | Required result |
| --- | --- |
| CSV `csv-001`, no ABN | Eligible community group may be reviewed/created without an identifier. |
| CSV `csv-002` and `csv-003`, shared all-zero ABN | Synthetic value never verified; branch remains distinct and held for parent resolution. |
| CSV `csv-004`, service | Hold until an evidenced deliverer and service publication path exist; never create a duplicate legal entity. |
| CSV `csv-005`, same name as `csv-001` | Candidate review, no automatic merge or unique-name failure. |
| CSV `csv-007`, malformed ABN | Quarantine; do not coerce into a numeric identifier. |
| NSW `0000123` versus VIC `0000123`, or NSW `123` | Distinct scoped keys; preserve zeros. Missing jurisdiction cannot match either. |
| Exact verified ABN, same legal entity, second provider | Multiple assertions/source links to one holder; replay creates no second entity. |
| Exact ABN and incorporation key point to different holders | Conflict hold even if a source link already exists. |
| Two concurrent verified-holder assignments for the same key | At most one accepted holder; loser receives a reviewable conflict. |
| Legacy shared ABNs, multiple legal rows and unknown kinds | Evidence backfill succeeds without fabricated verification, merging or UUID changes. |
| Cancelled ABN, failed lookup or changed resource `_id` | Preserve history; no automatic closure, reassignment or cross-resource match. |
| Classification/holder changes after approval | Stale approval refused; manual protection, visibility and suppression retained. |

P11 validation: compared this contract with the current schema, review/publication
constraints, P01/P04 evidence and CSV implementation; checked local document links
and diff whitespace. No runtime code, migrations, hosted data or deployments changed.
