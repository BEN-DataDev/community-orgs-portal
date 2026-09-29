# Confirmed-local initial-seed cohort v2

Decision date: 29 September 2026

Status: published. The immutable campaign, private review decisions and frozen
release remain the audit boundary.

## Correction boundary

Campaign `1079eb35-e8e0-46a4-8583-1af77f3d23ce` replaces campaign
`f3856dbc-8ec1-4c87-87f5-dd487e78e22f`. The first campaign incorrectly treated a
broad discovery postcode as evidence of portal relevance. Its 20 decisions have
been revised to `exclude`; the ten private run 35 identity decisions have been
revised to `reject`, making all ten associated change sets stale. The predecessor
is blocked as superseded and has zero publications.

The original campaign and manifest remain immutable audit evidence. They must not
be reused for publication.

## Frozen inputs

- ABR registry-seed release: 2
- Derived ACNC run: 34
- NSW registered-only release: 3
- Selection version: `initial-seed-local-cohort-v2`
- Cohort manifest: [initial-seed-local-cohort-v2.json](initial-seed-local-cohort-v2.json)
- Manifest SHA-256: `7352c3856b82544b55ec758fe024451f7064af693074d38d76e08fe0c87c227b`
- Server selection SHA-256: `2630b0665b74293654bba96b00a345dd741bfe594365f9cb2ba71e2aa5846858`

## Selection rule

Each of the ten selected candidates has:

1. an exact ABN match to a retained ACNC run 34 record; and
2. current external evidence of operation in Adelong, Batlow, Talbingo,
   Tumbarumba or Tumut.

The evidence URL and observed administrative locality are frozen in the manifest.
The configured postcode list remains an acquisition aid only. A discovery
postcode, DGR source flag, entity type or name similarity is not evidence of local
relevance and carries no decision weight.

Only the ten ordered version IDs in the manifest belong to this replacement
campaign. Cohort pinning does not itself triage, promote or publish a candidate.

## Private review outcome

All ten candidates were explicitly linked at cohort triage to their exact-ABN ACNC
run 34 records. Their notes separately record the current local-operation evidence;
DGR status is not used.

Private run 36 contains exactly those ten candidates and is
`publication_eligible=false` and `complete_snapshot=false`. Nine records have
revision-1 `create` decisions and private change sets limited to eligible
`entity_name` and `abn` values. SMART Animal Sanctuary already exists in the portal
under the same ABN and name; its provisional link was revised to an explicit
revision-2 `reject` because there was no field change to publish. This prevents a
duplicate organisation and avoids an artificial no-op change set.

## Publication

On 29 September 2026, the authorised Data Steward submitted and published initial
seed release `f80c76d3-233a-4505-bbcf-4e9fce5e5f25`, revision 1. Its frozen content
SHA-256 is
`dd5ecb73572775a7f4dfaf14d6a6b938e8ae45352294c0019c8f73222534d843`.
The release contained the nine active run 36 change sets and created nine public
organisations. The unchanged SMART duplicate was not a release item.

Hosted campaign readiness now reports ten records, three artifacts, one release,
one published release, zero identity pending, zero promotion pending, zero
validation blockers and zero field changes pending. Its state is `published` with
no blockers.

## Later full-source seed

On 30 September 2026, the separately authorised full retained-source publication
`ab7f6eeb-7ebd-457c-a754-8f827654f0a1` populated the operational database from the
complete deterministic union of the same three pinned artifacts. The bounded cohort
and release above remain immutable audit evidence; they are not the scope limit for
the later population. See [the full seed record](full-seed-union.md).
