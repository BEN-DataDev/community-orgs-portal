# Full retained-source seed union

Publication date: 30 September 2026 (Australia/Sydney)

Status: published, then corrected. The publication was over-broad; see
[Scope correction](#scope-correction) for the current state.

## Authorised boundary

An authenticated Data Steward published the complete deterministic union of these
retained, complete artifacts:

- ABR registry-seed release 2;
- derived ACNC run 34; and
- NSW registered-only registry-seed release 3.

The publication is `ab7f6eeb-7ebd-457c-a754-8f827654f0a1`. Its immutable selection
SHA-256 is
`1ea79843192b8f877409473378d458413acfeff62e55353cb74a81e766f5722a`.

The full-union path is authenticated, Data-Steward-only and resumable. It records a
frozen item set before applying bounded transactional batches. Names are never
identity keys. Records merge only on an exact ABN or an already verified NSW
incorporation identifier.

## Verified result

The three inputs contained 159,200 source rows. Exact-identifier deduplication
produced and published 158,662 canonical organisations:

- 157,242 represented ABNs;
- 1,420 represented NSW incorporation identifiers;
- 158,662 verified identifiers;
- 158,662 distinct public organisations; and
- zero organisation-owner grants to the publishing Data Steward.

The publication completed with zero pending items. Its recorded preparation actor
is `2b902bc4-832e-40fb-9c64-6948c57f5c65`; preparation completed at
`2026-09-29T22:16:13.937221Z` and publication at
`2026-09-29T23:19:32.688857Z`.

## Relationship to the bounded cohort

The earlier confirmed-local cohort and release remain immutable audit evidence of
the first reviewed publication workflow. They do not limit the later full retained-
source seed. The full-union publication supersedes that bounded scope for initial
database population without rewriting its campaign, review or release history.

Recurring NSW absence comparison remains disabled until a second complete,
scope-identical `REGISTERED` harvest exists. Later postcode absence must not be
treated as withdrawal.

## Scope correction

The union above bypassed candidate triage, validation-issue, three-source vetting
and publication-release gates, and published every in-scope ABR row regardless of
entity type. Correction `d10ac695-7cf3-4ab2-bc07-e22ea1beb11a` (rule
`community-entities-v1`, migration `20260930010000_correct_full_seed_scope.sql`)
was prepared at `2026-09-30T03:17:25Z` and applied at `2026-09-30T08:01:08Z`
through a management database session.

Of the 158,662 published organisations:

- 4,359 were kept: ABR `OIE`/`UIE` entities and every ACNC-backed ABN;
- 153,829 were removed; and
- 474 NSW associations were merged into a retained ABN entity — 457 on a unique
  normalised name and 17 on trigram name similarity (threshold 0.90, margin 0.10).

Item-level evidence remains in `ingestion.full_seed_items` and
`ingestion.seed_publication_correction_items`. Identity events for the removed rows
were collapsed to one `BULK_SEED_CORRECTION` event per batch.

**Open issue.** All 474 merges used names alone, which contradicts the rule above
that names are never identity keys and
[the ingestion strategy](data-ingestion-strategy.md) ("Do not automatically merge on
a fuzzy name score"). They require human review before being treated as verified.

**Review task (1 October 2026).** Admin → Seed merge review
(`/admin/ingestion/merges`, migration `20261001025644_seed_merge_review`) lists
each merge, similar-name matches first. A Data Steward decides alone:

- **Confirm** keeps the merge and records the review on the NSW identifier key.
- **Split** (note required) restores the association under its original
  organisation id from its full-seed item, unclaimed and public, moves its key
  back, restores the ABN entity's own full-seed incorporation values and removes
  the alias the merge added.

Decisions are final and kept in `ingestion.seed_merge_reviews`. A merge whose key
or incorporation number changed after the correction is refused and must be fixed
on the organisation or through identity review.

**Stewardship correction (1 October 2026).** The full-seed union recorded its
4,344 new organisations as `self_managed` although nobody held a role in them.
`20261001044648_unclaim_full_seed_organisations` moved each to `unclaimed` with an
appended stewardship event that references the publication, and the stewardship
trigger now treats full-seed organisations as imports.

**Closed paths (applied 1 October 2026).**
`20260930230051_ingestion_acl_hardening.sql` revokes `prepare_full_seed_union`,
`apply_full_seed_union_batch` and `full_seed_union_status` from client roles, and
`20260930230128_retire_seed_correction_bypass.sql` removes the correction's trigger
bypasses. Future seeding must use
the governed triage and publication-release path.
