# National ABN bulk registry seed (P33)

Status: implemented locally on 22 September 2026 and qualified against the complete
23 September 2026 national release on the local operator workstation. The hosted
source is enabled at approval revision 1 and the qualified release is finalized as
private registry-seed release `2`. No candidate has been triaged, promoted or
published.

## Boundary

`ingestion.abr_bulk` reads a separately downloaded, inventoried weekly ABN Lookup
bulk release. It does not use ABN Lookup web-service credentials and does not make
network or database connections. It emits private `registry-seed-v1` artifacts for
the deployed P31 candidate store; it cannot triage, create or publish an organisation.

The official resource list currently declares two ZIP resources,
`public_split_1_10.zip` and `public_split_11_20.zip`. Each archive contains multiple
XML members, so the adapter inventories both resource files and all 20 XML sequence
numbers. The release is complete only when:

- both configured files exist and match their independently recorded SHA-256;
- every XML member parses and its `TransferInfo.RecordCount` matches the streamed
  number of `ABR` records;
- member sequence numbers are exactly `1..expected_member_count` without gaps or
  duplicates;
- every member reports the configured extract timestamp;
- every retained or scanned ABN passes the published ABN checksum;
- no selected ABN occurs in more than one member; and
- no source-reported transfer error or record/schema error occurs.

Any failure produces a partial manifest with `complete_snapshot=false`. P31 rejects
partial releases from promotion. Checksum mismatches retain the observed hash only
inside failure detail because the P31 part contract intentionally rejects a claimed
expected/observed match when the values differ.

The official XSD declares `ExtractTime` as `xsd:dateTime`, for which a timezone is
optional. The qualified 23 September release uses a timezone-less source value.
P33 preserves and compares that provider value exactly; it does not invent a
timezone. `observed_at` remains a separate RFC 3339 UTC timestamp recorded by the
operator run. The release also uses the literal `none` in the required `Transfer`
`error` attribute to report success; P33 accepts only the empty synthetic-fixture
sentinel or the qualified `none` sentinel and continues to reject every other value.

## Selection and mapping

Every source record is streamed, but only records whose main business postcode is
configured or whose ABN is explicitly known are retained. A registered business
postcode is discovery evidence, not evidence that the entity provides a local
community service.

Candidate identity is the 11-digit ABN. Raw `ABR` XML structure is retained as a
private JSON object. Typed candidate assertions preserve:

- legal/main entity name and ABN;
- ABN status and effective date;
- record update date and entity type code/text;
- main-location state and postcode;
- ASIC number and GST status/date; and
- repeated other/trading/business names and repeated DGR entries without collapsing
  them.

These source-specific assertions are candidate evidence. P35 must define reviewed
cross-source resolution and P36 must define their public destinations before
publication.

## Checkpoints and private artifacts

Each successfully parsed resource part receives a `0600` checkpoint keyed by the
release, parser, file hash, extract time and configured selection. A rerun still
rehashes the source file, but can skip XML parsing when that complete checkpoint
matches. Changed selection, release metadata, parser version or source bytes invalidates
the checkpoint.

The output directory must not already exist and is created with mode `0700`.
`manifest.json`, `candidates.json` and `stage.sql` are created once with mode `0600`.
For a large real release, render the separately tested resumable chunked SQL and
apply that instead of the one-shot `stage.sql`. Store the source files, checkpoints
and outputs outside Git.

## First-release execution environment

Run the first qualified release manually on the local operator workstation, not in
a Vercel build or function. Vercel remains the portal and review host; it has no
role in downloading, parsing or retaining the bulk files. Supabase receives only
the separately inspected private staging result through the restricted ingestion
identity.

The proposed workstation base path is:

```text
/home/akeown/private/community-orgs/abr/
├── config/
├── releases/<release-id>/
├── checkpoints/<release-id>/
└── outputs/
```

The base path and its parent must remain outside the repository, be accessible only
to the operator account and be excluded from unapproved synchronisation, indexing
and backup destinations. At-rest encryption is recommended as defence in depth but
is not a documented ABN bulk-extract access condition or a P33 completeness
requirement. For the first release, the owner has accepted use of a Windows volume
without BitLocker and does not intend to enable it. The storage approval must record
that risk and the compensating account-access, physical-security, copy and retention
controls. When the workstation uses WSL, prefer its Linux filesystem over `/mnt/c`
unless the Windows storage and copy lifecycle have also been approved. Prevent
sleep, restart and loss of network connectivity during the run.

Before downloading a real release, record both the source-acquisition approval and
approval of this filesystem location, including retention, backup and deletion
responsibilities. A directory existing with restrictive permissions is necessary
but is not approval. A VM or object store is not required for the first release;
reassess central execution and durable artifact storage before enabling unattended
recurring acquisition.

The first-release decision and qualification result are recorded under approval reference
[`P33-WS-2026-09-23`](operations/p33-first-release-approval.md). Acquisition, scope,
path, unencrypted-volume risk, absence of backup and retention hold are approved for
one qualified acquisition.

## Running a qualified release

Start from
[`abr-bulk-release.example.json`](../tools/ingestion/python/config/abr-bulk-release.example.json).
Before running, replace its release ID, observation/extract timestamps and placeholder
hashes using one coherent download. Confirm the current official resource list,
licence, filenames, resource IDs, XSD and member count rather than assuming the
example remains current.

From `tools/ingestion/python`:

```sh
python3 -m ingestion.abr_bulk \
  --config /home/akeown/private/community-orgs/abr/config/<release-id>.json \
  --input-dir /home/akeown/private/community-orgs/abr/releases/<release-id> \
  --checkpoint-dir /home/akeown/private/community-orgs/abr/checkpoints/<release-id> \
  --output-dir /home/akeown/private/community-orgs/abr/outputs/<release-id>
```

The release-specific output directory must not already exist; the command creates
it. Do not place database passwords in the command, configuration or shell history.
Exit code `0` means the configured scoped snapshot is complete. Exit code `1` means
private partial evidence was emitted and must not be staged as complete. Configuration,
filesystem and output-collision failures exit `2`. Inspect the manifest before
staging it in an explicitly selected database with an enabled
`(abr-bulk, resource_id)` source registration.

For the qualified release, render bounded transactions from the inspected artifacts:

```sh
python3 -m ingestion.registry_seed_chunked_sql \
  --manifest /home/akeown/private/community-orgs/abr/outputs/<release-id>/manifest.json \
  --candidates /home/akeown/private/community-orgs/abr/outputs/<release-id>/candidates.json \
  --output /home/akeown/private/community-orgs/abr/outputs/<release-id>/stage-chunked.sql \
  --batch-size 250
```

The chunked protocol validates exact batch replays, rejects changed replays, and
atomically finalizes only after candidate count and aggregate hash checks pass.
Temporary upload rows cannot be triaged, promoted or published and are removed only
after successful finalization and replay verification.

## Validation

The synthetic suite covers plain, namespaced, ZIP and GZIP XML; multiple XML members
per ZIP; main and individual entity names; repeated names/DGRs; postcode and known-ABN
selection; checksums; source record counts; sequence completeness; checkpoint replay;
missing/malformed parts; duplicate ABNs; SQL encoding; and private output permissions.

```sh
python3 -m unittest tests.test_abr_bulk -v
python3 -m unittest discover -s tests -v
```

The complete ingestion suite passes 99 tests.

## First real release qualification

The approved workstation run completed on 23 September 2026:

- release ID `2026-09-23` and provider extract value
  `2026-09-23T12:33:03`;
- both configured ZIP resources matched their independently calculated SHA-256;
- all 20 XML members appeared exactly once in sequence;
- 20,545,089 source records matched the member and part counts;
- 157,156 unique candidates matched the configured 23-postcode scope;
- both checkpoint files replayed without reparsing;
- `completion=complete`, `complete_snapshot=true` and no errors; and
- source, checkpoint and output files use owner-only permissions.

The first attempt failed closed with zero candidates because the real source uses
the XSD-valid timezone-less `ExtractTime` and `Transfer error="none"` conventions
that were absent from the synthetic fixtures. The parser now preserves the source
timestamp without inventing a timezone and accepts only `none` or the existing
empty fixture sentinel as successful transfer states. The new real-format regression
and all 99 ingestion tests pass. The retained partial attempt is not eligible for
staging.

The complete one-shot `stage.sql` is approximately 422 MB. It exceeded the restricted
worker/container and hosted statement limits without committing a release. The
replacement `stage-chunked.sql` contains 629 resumable batches of 250 candidates,
is mode `0600`, and has SHA-256
`92b09b044eff04f592925ab3dc0b6f79bb65a72b01bf7736cc5aca2dcc5eef80`.

After the platform administrator enabled the source, the owner explicitly approved
upload to hosted Supabase private staging and atomic finalization. Hosted migration
`20260923014057_chunked_registry_seed_staging` supplied the restricted upload
protocol. All 157,156 candidates were committed to upload `1`; the first finalizer
transaction timed out and rolled back cleanly, then a restricted-role retry with a
bounded ten-minute timeout finalized release `2`. Idempotent replay returned the
same release, and exactly 157,156 redundant temporary rows were cleared.

The hosted audit records 2 complete parts, 20,545,089 source records, 157,156
in-scope release memberships and zero triage or promotion rows. Organisation counts
remained 7 total and 6 public. Staging is private and does not authorise promotion
or publication.

## Source qualification

- [ABN Lookup bulk extract](https://abr.business.gov.au/Tools/BulkExtract)
- [data.gov.au ABN bulk resource list](https://data.gov.au/data/dataset/abn-bulk-extract/resource/469c8c2c-0be5-45b2-90d7-c42f637f3323)
- [ABN Lookup bulk extract readme](https://data.gov.au/data/dataset/abn-bulk-extract/resource/3b975e4f-af2f-4de7-a20e-6dcb3f67805c)

The official pages identify a weekly XML extract and Creative Commons Attribution
3.0 Australia licensing. The local fixture is invented and does not reproduce real
registry records.
