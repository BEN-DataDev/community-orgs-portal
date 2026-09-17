# ACNC website normalisation v3

Status, 17 September 2026: **F05 release gate complete.** The operator reports
that run 8 has been approved and published and all post-publication checks have
been verified. This closure records the user’s confirmation; it is not a new
automated validation run.

Parser `acnc-ckan-v3` and mapping `acnc-register-fields-v3` qualify the bare-domain
format observed in the retained pilot. This is a syntax rule, not a claim of
website ownership, reachability or register verification.

For example, `smartrescue.org.au` becomes `https://smartrescue.org.au`. The original
text remains in the raw envelope and the assertion's `source_values`. An explicit
`bare-dns-https-v1` marker and warning record that the scheme was inferred. The
private review displays the proposed URL alongside original evidence. Nothing is
automatically approved or published.

Only bare ASCII DNS names with at least two labels and an alphabetic final label
are eligible, with an optional trailing slash. Label/hostname length and hyphens
are validated. Schemeless paths, query strings, fragments, ports, credentials,
IP addresses, single-label hosts, Unicode/punycode names and reserved/internal
suffixes remain unqualified and quarantine the record. Existing valid explicit
lowercase HTTP(S) URLs retain their scheme and value; no HTTP-to-HTTPS upgrade is
performed. No website is fetched by normalisation.

The v2 manifest remains unchanged in `acnc-register-v1.json` for historical
evidence. The active manifest is `acnc-register-v3.json`. The new migration updates
mapping tokens, so unconsumed approvals require fresh review. Both explicit v2 and
v3 parser/mapping pairs remain recognised for retained evidence and replay.

Validation:

- 44 Python tests pass, including accepted bare names, explicit URLs, nulls,
  malicious/ambiguous input, preserved raw evidence and version markers.
- The isolated PostgreSQL suites pass with the new migration. The added test
  preserves a v2 quarantine run while staging v3, checks raw and normalised values
  in review, requires fresh approval, round-trips the URL through publication and
  anonymous reads, and verifies an idempotent retry.
- Reprocessing the six retained run-6 records produces a **complete** envelope:
  six accepted, zero quarantined, 136 supplied valid organisation-column values,
  278 absent, zero invalid and zero unmapped. Raw hashes, observation time and
  source identities are preserved. Original run 6 and partial run 7 remain intact.
- The retained-pilot SQL suite also passes in the disposable database: six accepted
  records, explicit URL inference, unchanged v1/v2 evidence, no duplicate identities
  on retry and no transferred approvals.

The live replay key is `acnc-reprocess-run-6-v3`, linked directly to complete
acquisition run 6. It does not replay the partial run 7 or replace its evidence.

Following explicit user approval, [the v3 migration](../supabase/migrations/20260917020000_acnc_website_normalisation.sql)
was applied as deployment `20260916232821_acnc_website_normalisation`. The replay
was staged as **run 8: complete, six accepted, zero quarantined**, at
`2026-09-16T23:28:32.843439+00:00`. Its observation time remains the original
`2026-09-16T04:47:41.708096+00:00`.

Hosted checks at staging time, before operator approval/publication, confirmed:

- Runs 6 and 7 and all pre-existing version hashes are unchanged.
- Existing links and organisation/approval/publication counts are unchanged.
- Run 8 has six versions and no reviews, field approvals or publications.
- The website preview contains both the HTTPS value and original bare-domain text.
- The existing link for ABN 75349327058 remains available for fresh review.
- Anonymous access returns only the two previously published pilot facts; the
  private replay report remains inaccessible.

## Post-publication verification — 17 September 2026

The operator confirmed approval and publication, then confirmed all follow-up
checks: hosted signed-out access, approved fields and source attribution/dates,
run-8 coverage review, exclusions/suppression and duplicate checks. The route-guard
fix allows public organisation reads while retaining protected submissions and
admin routes. Local HTTP checks covered the list, organisation sections and
navigation data; regression and type checks passed before operator verification.

The F05 release gate is complete on that basis. The staging counts above remain
historical evidence, not current approval/publication totals. No new numeric
publication totals or coverage artifact are asserted by this documentation update.

Next: resume acquisition job controls and scheduling work. This status does not
itself enable scheduled acquisition or automatic publication; broader sources
still require their own qualification and field-coverage gates.
