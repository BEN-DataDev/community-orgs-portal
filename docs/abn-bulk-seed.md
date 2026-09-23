# National ABN bulk registry seed (P33)

Status: implemented locally on 22 September 2026. No national bulk file was
downloaded, no candidate was staged, and no source was enabled by this change.
The first real release remains an explicit operator acquisition and private-staging
step. On 23 September 2026 the local operator workstation was selected for that
first run; this does not by itself approve acquisition or its private storage path.

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
Store the source files, checkpoints and outputs outside Git.

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
to the operator account, reside on approved encrypted storage and be excluded from
unapproved synchronisation, indexing and backup destinations. When the workstation
uses WSL, prefer its Linux filesystem over `/mnt/c` unless the Windows storage and
copy lifecycle have also been approved. Prevent sleep, restart and loss of network
connectivity during the run.

Before downloading a real release, record both the source-acquisition approval and
approval of this filesystem location, including retention, backup and deletion
responsibilities. A directory existing with restrictive permissions is necessary
but is not approval. A VM or object store is not required for the first release;
reassess central execution and durable artifact storage before enabling unattended
recurring acquisition.

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
applying `stage.sql` to an explicitly selected database with an enabled
`(abr-bulk, resource_id)` source registration.

## Validation

The synthetic suite covers plain, namespaced, ZIP and GZIP XML; multiple XML members
per ZIP; main and individual entity names; repeated names/DGRs; postcode and known-ABN
selection; checksums; source record counts; sequence completeness; checkpoint replay;
missing/malformed parts; duplicate ABNs; SQL encoding; and private output permissions.

```sh
python3 -m unittest tests.test_abr_bulk -v
python3 -m unittest discover -s tests -v
```

The complete ingestion suite passes 95 tests.

## Source qualification

- [ABN Lookup bulk extract](https://abr.business.gov.au/Tools/BulkExtract)
- [data.gov.au ABN bulk resource list](https://data.gov.au/data/dataset/abn-bulk-extract/resource/469c8c2c-0be5-45b2-90d7-c42f637f3323)
- [ABN Lookup bulk extract readme](https://data.gov.au/data/dataset/abn-bulk-extract/resource/3b975e4f-af2f-4de7-a20e-6dcb3f67805c)

The official pages identify a weekly XML extract and Creative Commons Attribution
3.0 Australia licensing. The local fixture is invented and does not reproduce real
registry records.
