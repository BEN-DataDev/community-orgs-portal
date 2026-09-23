# P33 first-release operational approval

Approval reference: `P33-WS-2026-09-23`

Decision date: 23 September 2026

Status: acquisition qualified and explicitly approved for private hosted staging;
finalized as private registry-seed release `2`

## Acquisition scope

The project owner approved acquisition of one current Australian Business Register
bulk extract for private candidate discovery using the existing 23-postcode Snowy
Valleys scope recorded in the P33 configuration example.

This approval does not authorise automatic candidate promotion, organisation
creation, identity merging, field approval or publication. Evidence remains under a
hold pending P35 triage and P36 publication/withdrawal validation.

## Execution and storage

The first qualified release is approved to run manually on the local operator
workstation. Its approved base path is:

```text
/home/akeown/private/community-orgs/abr
```

The Windows volume backing WSL is not BitLocker-protected. The project owner does
not want to enable BitLocker and accepts the resulting at-rest risk. The source
materials reviewed for P33 do not establish disk encryption as an access condition.

The project owner confirmed that the directory is not synchronised to an unapproved
cloud service and is not backed up. Loss of the workstation copy is an accepted
availability risk; it does not permit an untracked secondary copy.

Access is limited to the workstation operator account. Source files, configuration,
checkpoints, outputs and any backup copies remain outside Git and must be inventoried
under the same hold and deletion process.

## Authorised implementation

The project owner authorised:

- creation of the private workstation directory;
- registration of the `abr-bulk` source in the hosted database, initially disabled;
- download of approximately 1 GB of current release files after the backup-status
  gate is resolved; and
- execution of the P33 qualification checks.

Source enablement remains a separate, audited platform-administrator action in
**Admin → Source approvals**. A complete P33 run may be staged privately only after
that action. Promotion and publication remain out of scope.

The platform administrator enabled the source at approval revision `1` on
23 September 2026. The recorded reason identifies release `2026-09-23`, this
approval reference, 20,545,089 qualified records and 157,156 scoped candidates, and
states that candidate promotion and publication are not authorised. After being
informed that the payload would leave the workstation for the hosted production
Supabase private staging schema, the project owner explicitly approved upload of all
157,156 postcode-scoped candidates and atomic finalization. That approval does not
extend to triage, promotion or publication.

## Qualification result

The `2026-09-23` release completed qualification on the approved workstation:

| Check                      | Result                                                             |
| -------------------------- | ------------------------------------------------------------------ |
| ZIP SHA-256, part 1        | `99847bf821907e53d2e14776c8ae943f501b4f84b118111e3fe21a8afb0b4da1` |
| ZIP SHA-256, part 2        | `b7efe378f31f4eb882fdfccc15d67663865cdfccc548256a14aabff9c0990a12` |
| XML member sequences       | `1..20`, complete and unique                                       |
| Source records             | 20,545,089                                                         |
| Scoped unique candidates   | 157,156                                                            |
| Completion                 | `complete`; `complete_snapshot=true`; zero errors                  |
| Checkpoint replay          | Both parts reused; candidate count unchanged                       |
| Candidate artifact SHA-256 | `1aff3c7d0f54e2de457a0bcb0f1107c0609ed2f0ba11cd487a770cbefda98af3` |
| Manifest artifact SHA-256  | `b32e639d5f5647dc987917add273c44e66b059bdd2791740e9661072880b9494` |
| Staging artifact SHA-256   | `ce7ed9f02869bcfaba4b02d57eaadee7129b7feb40f59f50bdc8032f5b2c79d3` |
| Chunked staging SHA-256    | `92b09b044eff04f592925ab3dc0b6f79bb65a72b01bf7736cc5aca2dcc5eef80` |

Hosted migration `20260923010117_register_abr_bulk_source` is recorded. The source
is deployed with `enabled=true` and approval revision `1`. Hosted migration
`20260923014057_chunked_registry_seed_staging` adds bounded, replay-safe private
upload and atomic finalization.

## Private staging result

The approved payload was uploaded as 629 transactions of at most 250 candidates.
The original one-shot transport did not commit a release. The first chunked
finalizer attempt exceeded the database statement timeout and rolled back its whole
transaction; all 157,156 temporary upload rows remained intact. A restricted-role
retry with a bounded ten-minute timeout finalized registry-seed release `2` at
`2026-09-23T02:32:51.066419Z`.

The idempotent finalizer replay returned release `2`. The cleanup then removed
exactly 157,156 redundant temporary upload rows while retaining the finalized
candidate/version/membership evidence. The post-cleanup production audit found:

- one complete release with 2 complete parts and 20,545,089 source records;
- 157,156 candidates, versions and in-scope release memberships;
- zero triage and promotion rows;
- source enabled at approval revision 1;
- zero remaining temporary candidate payload rows; and
- unchanged organisation counts of 7 total and 6 public.

The database canonical JSON hashes are
`482f1a7a51888bc566715e322f43231a629e94d5bfed66ce70f97df2f6de82dd`
for the manifest and
`8344fc52cec290d144e18fabce5a92a8c1fa17be4b32918d8df1c1aeaad51a53`
for the ordered candidate set. These intentionally differ from the byte hashes of
the pretty-printed workstation artifacts.

An initial qualification attempt failed closed before retaining any candidates due
to two previously untested but XSD-valid real-source conventions: a timezone-less
`ExtractTime` and `Transfer error="none"`. The corrected parser preserves the source
timestamp, recognises only the qualified success sentinel and retains rejection of
all other source error values. The partial attempt remains separately inventoried
and is not eligible for staging.
