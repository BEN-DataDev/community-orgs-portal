# ACNC acquisition jobs

Updated 23 September 2026: the acquisition migration and restricted worker LOGIN
are deployed to Supabase project `gqltsfijginclwszrcfj`. The worker is installed
and running on **AKHOME** in Docker Desktop. Password authentication, verified TLS
and queue processing succeeded. The first manual live refresh completed as
**run 9**, with six accepted records and zero quarantine. The postcode 2730 pilot
is configured for a monthly 30-day refresh. The first scheduled enqueue is due
after `2026-10-19T03:18:23Z`; the daily Vercel cron should pick it up at the next
check after that due time. The portal changes are now live on Vercel.

The 23-postcode Snowy Valleys expansion is also deployed. Hosted configuration
revision 3 contains the complete cohort, preserves the monthly schedule and due
time, and the rebuilt AKHOME worker is polling. The first expanded manual job,
`226f831f-ad14-40e1-8dec-f24bf2fb46c6`, finished as private run **30** on
23 September 2026. It retrieved 625 rows across seven pages, accepted 618 and
quarantined seven schemeless website values containing paths or queries. It had
zero acquisition errors and zero out-of-scope rows. The run is partial and
publication-blocked; it created no reviews, approvals, promotions, publications or
organisations.

The owner approved [P34a cross-source staged validation](staged-validation-resolution.md)
in response. P34a will expose all failed fields/records in the operator UI, retain
revision-fenced decisions and create a separately revalidated derived run. Run 30
and its raw quarantine evidence remain immutable and private.

## Deployment record

- `acquisition_jobs` applied through Supabase MCP as version `20260917014227`
  (local migration `20260917030000_acquisition_jobs.sql`).
- `acquisition_worker_login` applied as version `20260917014304`
  (local migration `20260917040000_acquisition_worker_login.sql`).
- Database role `community_orgs_acquisition` has LOGIN, NOINHERIT, a connection
  limit of 2, no superuser/BYPASSRLS privileges, and only `ingestion_worker`
  membership. It explicitly assumes that role for each worker transaction.
  Statement/lock/idle-transaction timeouts are set to 30/10/30 seconds.
- A randomly generated password was assigned through the Supabase management API
  as a SCRAM verifier. Its plaintext exists only in the local owner-readable
  password file, outside the repository and container image. The worker receives
  that file through a read-only mount; no management token is passed to it.
- Hosted checks confirmed zero jobs/configurations, no anonymous dashboard access,
  no authenticated scheduler access and no direct job-table writes for the LOGIN.
  A real container connection subsequently authenticated as the new LOGIN,
  assumed `ingestion_worker`, and completed an idle queue claim. Repeated polls
  and an explicit container restart both succeeded. The actual execution role
  has no portal-schema access and no direct job-table UPDATE privilege.
- Container `community-orgs-acquisition-worker` runs as UID/GID 1000 with a
  read-only filesystem, dropped capabilities, no published ports, a 256 MiB
  memory limit and a half-CPU limit. It checks the queue every 60 seconds after
  the previous invocation finishes and uses Docker's `unless-stopped` restart
  policy. Logs are limited to three 5 MiB files.
- AKHOME is a WSL2 environment using Docker Desktop. The container resumes when
  Docker Desktop starts, unless explicitly stopped. AKHOME must be awake and
  connected, with Docker Desktop running; this is not an independent cloud host.
- The postcode 2730 configuration was created with the previously reviewed licence
  and no schedule. On 19 September 2026, the operator decision was monthly refresh:
  hosted configuration revision 2 set `interval_hours=720` and
  `next_due_at=2026-10-19T03:18:23Z`. Its audit event preserves the same authorised
  configuration actor; no browser session or MFA session was impersonated.
- Manual job `5e68af3a-db56-47a1-ba49-b4166ef94219` completed in one attempt at
  `2026-09-17T02:37:19Z`, staging run **9**: one page, six source records, six
  accepted, zero quarantine, zero errors. The job was enqueued through the
  management API, with no fabricated browser actor. It is ready for review.
  All six record versions match run 8, confirming unchanged-version reuse. Portal
  organisation counts remained seven total/six public, and no publication occurred.
- Production portal deployment succeeded through the renewed Vercel CLI login:
  `dpl_9tF1mk7odunPnGwdPXjwjzf4mng3`, status `READY`, aliased to
  [community-orgs-portal.vercel.app](https://community-orgs-portal.vercel.app).
  Source/assets/configuration files were deployed without `.env` or credential
  files. This resolves the earlier connected-tool review-size rejection.
- Hosted HTTP checks passed: homepage, organisation list and a representative
  organisation's overview/contact/legal/operations/finance pages returned 200
  without authentication; acquisition/review pages redirected to sign-in; an
  unauthenticated cron request returned 401. Signed-in job controls were subsequently
  verified by the operator in the recovery checks below; run 9 itself used the
  management API.
- Open [Acquisition jobs](https://community-orgs-portal.vercel.app/admin/ingestion/jobs)
  or [review run 9](https://community-orgs-portal.vercel.app/admin/ingestion?run=9)
  after signing in. No second import or publication was triggered by deployment.
- This was a working-tree deployment. Git changes remain uncommitted; a future
  Git-triggered deployment must include these changes to preserve this release.
- Multi-postcode migration `multi_postcode_acquisition` was applied on
  19 September 2026. Production deployment
  `dpl_37dYPbzG7FQruYZiJ5MhKG7nCA3a` reached `READY` and was aliased to the
  production URL. The worker image was rebuilt as
  `community-orgs-acquisition:local` and its container recreated successfully.
- Hosted configuration revision 3 contains all 23 reviewed postcodes, retains
  `interval_hours=720` and keeps `next_due_at=2026-10-19T03:18:23Z`. The change
  preserved the existing authorised configuration actor and cancelled any active
  work; no expanded job was queued during deployment.

## Operating the AKHOME worker

The image is `community-orgs-acquisition:local`. Deployment files are in
`tools/ingestion/deploy/{Dockerfile,compose.yaml,poll-worker.sh}`. Source code is
copied into the image at build time, so later repository edits require rebuilding.
The host credential directory is `/home/akeown/.config/community-orgs-acquisition`
(mode 0700); `pgpass`, `worker.env` and `supabase-ca.crt` are mode 0600. Keep these
files out of Git and do not paste the password or password-file contents into logs.

The direct project address is IPv6-only and was unreachable from AKHOME. The
worker uses the project's shared session pooler at
`aws-0-ap-southeast-1.pooler.supabase.com:5432`, with the custom role/project username.
The Supabase CA was downloaded from its HTTPS certificate distribution endpoint;
`sslmode=verify-full` checks the server certificate and hostname. This follows the
[Supabase connection guidance](https://supabase.com/docs/guides/database/connecting-to-postgres)
and [TLS guidance](https://supabase.com/docs/guides/platform/ssl-enforcement).

From the repository root:

```sh
# Check status and recent output (an empty queue prints {"status": "idle"}).
docker ps --filter name=community-orgs-acquisition-worker
docker logs --tail 20 community-orgs-acquisition-worker

# Stop or resume queue processing on this computer.
docker stop community-orgs-acquisition-worker
docker start community-orgs-acquisition-worker

# Rebuild and recreate after worker code changes.
ACQUISITION_CONFIG_DIR=/home/akeown/.config/community-orgs-acquisition \
  docker compose -f tools/ingestion/deploy/compose.yaml up -d --build
```

The example systemd units remain available for a future standalone Linux host;
they were not installed on AKHOME. The Docker image contains the PostgreSQL client,
so AKHOME does not need a host `psql` installation. No existing Docker Desktop
startup settings or unrelated containers were changed.

## Operator workflow

Open **Admin → Import review → Acquisition jobs** (`/admin/ingestion/jobs`).
A platform administrator configures an existing live ACNC resource with 1 to 50
unique four-digit postcodes, the exact reviewed CKAN licence title and a schedule.
The initial schedule is **Off**. Source approval remains managed in `/admin/sources`.

An ingestion operator can select **Run acquisition** when the source is enabled
and configured. Repeated submissions reuse the existing active job. The page
shows the latest 50 jobs, attempts, availability, lease expiry and completion,
with a link to the staged import. **Refresh status** reloads these details.
Complete imports still need the existing match/review/approval/publication steps.
Partial and failed acquisitions retain their evidence and block publication.

### Snowy Valleys expansion target

The reviewed [postcode discovery scope](snowy-valleys-postcode-scope.md) contains
23 postcodes: 13 ABS Postal Areas overlapping the Snowy Valleys LGA and 10 directly
touching its boundary. The local migration, configuration RPC, admin form, CKAN
worker and bulk fallback accept a canonical list of 1 to 50 postcodes. CKAN applies
the list as one array-valued filter, preserving one paginated result and the global
1,000-record cap. The source currently reports 626 matching records, within that
bound. The migration, portal, rebuilt worker and hosted 23-postcode configuration
are deployed. Adjacent-postcode results must remain private until evidence shows
service delivery within Snowy Valleys.

Saving configuration cancels active work for that resource and records the change
in a private audit table. A paused source cannot enqueue, renew a lease, save an
acquisition checkpoint or finish staging. Pausing then re-enabling also invalidates
old jobs through the source approval revision. The next worker check marks them
cancelled; a subsequent manual/scheduled submission can create fresh work.

## Execution and recovery

`ingestion.worker` processes at most one job per invocation, using the existing
ACNC v3 parser and staging service. Limits are 100 records/page, 5 pages, 500
records total, 120 seconds of HTTP budget, 10-second request timeouts and 2 MiB per
response. Requests retain existing bounded retry/backoff and licence/schema checks.

Private database functions claim jobs and grant a five-minute lease with a new
UUID token on every claim. The worker checks source approval and renews its lease
before each HTTP operation. Expired tokens cannot checkpoint or stage, even if a
replacement worker has already acquired the job. Short queue transactions are
serialised with an advisory lock; source row locks coordinate completion with
source pause operations. At most one active job exists per source/resource.

A completed acquisition envelope is saved as an immutable private database
checkpoint before staging. A replacement worker resumes staging from that same
envelope and observation time. Staging and job completion commit atomically.
If a process dies before saving that checkpoint, the next attempt restarts the
bounded acquisition with a fresh observation time. **Pages are not combined across
attempts:** CKAN filtered pagination does not guarantee a stable snapshot.

Infrastructure failures retry after 2 and 4 minutes, with a maximum of three job
attempts. Crashed processes recover after lease expiry; the third expired lease
ends the job as failed. Partial/failed source envelopes are staged as terminal
results for inspection, rather than repeatedly fetching an unqualified source.
Worker output includes job/run IDs, completion and error class, never database
connection details or raw provider errors. Provider errors remain in private
staging evidence. The checkpoint duplicates the staged envelope in private storage;
retention/pruning remains a separate maintenance task.

## Deployment

1. Apply `supabase/migrations/20260917030000_acquisition_jobs.sql` after the existing
   ingestion migrations, then deploy the application. Deploy the migration first:
   the cron route now calls `community_orgs.enqueue_due_acquisitions()`.
2. Provision a dedicated PostgreSQL LOGIN with membership in `ingestion_worker`,
   no superuser/BYPASSRLS privileges and no portal role memberships. This is the
   existing staging role; it has no publication API access. Keep its password in
   the worker host's secret storage. Do not use the browser key or service-role
   API key as worker credentials.
3. Install Python 3.10+ and the PostgreSQL `psql` client on the worker host, and
   deploy `tools/ingestion/python`. There are no additional Python dependencies.
   Configure libpq with `PGSERVICE`/`PGSERVICEFILE`, or `PGHOST`, `PGPORT`,
   `PGDATABASE`, `PGUSER`, `PGPASSFILE`, `PGSSLMODE=verify-full` and the appropriate
   root certificate. Set `PGCONNECT_TIMEOUT=10`. The password file must be readable
   only by the worker account. Connection details are never command arguments.
4. From `tools/ingestion/python`, invoke `python3 -m ingestion.worker` periodically.
   Example systemd service/timer files are in `tools/ingestion/deploy`; adapt their
   installation path and create the specified OS account and environment file.
   The timer checks every minute and the service processes one job per invocation.
   A container/job runner can invoke the same command. No inbound worker HTTP
   endpoint is required. Monitor nonzero exits and jobs remaining queued without
   attempts. Provisioning files are examples, not installed services.
5. Configure the pilot postcode cohort and licence in the UI, leave scheduling off, and
   manually queue one import. Verify job completion, retained evidence, import
   review, and source pause recovery before enabling a schedule.

The existing authenticated `/api/cron` runs daily on Vercel. After its existing
maintenance tasks it enqueues at most 20 due source configurations; it never calls
CKAN or publishes. Schedules support 1, 7 or 30 days and first become due one full
interval after saving. A delayed cron coalesces missed intervals into one job;
next due time advances from the actual scheduler check. Paused sources do not
advance their due time. On re-enablement an overdue schedule can enqueue at the
next check. Counts in the cron response describe due configurations processed,
including any already-active job reused. The worker timer and acquisition schedule
serve separate purposes: polling the queue does not enable a source schedule.

## Validation and limits

- All 51 Python tests passed, including worker lease loss, checkpoint reuse,
  staging failure, partial evidence, idle behavior and credential-safe invocation.
- Disposable PostgreSQL 16 ingestion suites passed, including the new permissions,
  stale configuration, single active job, token fencing, checkpoint recovery,
  bounded retry, pause/re-enable, scheduler and configuration audit cases.
- The actual Python worker completed a fixture acquisition through `psql` with a
  dedicated non-superuser test login, producing a complete private staging run. A second unchanged run reused both
  record versions; changed fixture records produced new versions; a schema failure
  produced a failed private run without removing retained versions.
- Route/SSR and Chromium checks covered run availability, paused sources, default
  schedule, postcode validation and the review link. These browser checks used
  rendered fixture HTML; hosted navigation/form submission remains unverified.
- Route and cron regression tests, Svelte checking, targeted ESLint and production
  build passed. The build reported existing sourcemap/annotation and optional
  Sharp dependency warnings.

Existing ingestion suites continue to exercise unchanged replay, legitimate
changes, manual-edit protection, suppression/withdrawal and failed/partial runs.
This increment does not infer closures or delete missing organisations, even for
complete filtered results. National bulk acquisition, stable native-ID
qualification across resource releases and broader operational sizing remain
outstanding. The requested recovery scenarios are now verified below. P26 application/worker code is implemented and its database migration is deployed;
worker hosting, database connectivity and a six-record live refresh are verified
on AKHOME. The production portal is deployed and public/protected-route HTTP
checks passed. The operator has now confirmed the signed-in queue/restart,
source-pause and re-enable checks below. Controlled active-job interruption,
manual-edit protection, withdrawal replay and source-failure checks also passed
in the disposable database; see the controlled recovery results below.

## Operator recovery checks

Tested on: 2026-09-17
Acquisition scheduling: Off

| Check                             | Job ID / Run ID                      | Observed result                                                            | Pass / Fail |
| --------------------------------- | ------------------------------------ | -------------------------------------------------------------------------- | ----------- |
| Worker stopped, then restarted    | d19e3c07-867b-40ef-b0e0-ec28d57674bd | Same job completed, with one staged import and no duplicate organisations. | Pass        |
| Source paused with a queued job   | d04b0c07-2d28-4482-a346-b25de104c7ea | The queued job was cancelled, and new acquisition requests are blocked.    | Pass        |
| Fresh job after source re-enabled | 1aa2064f-bbe2-40fe-8472-7433e92ba442 | Fresh job completes; the cancelled job stays cancelled.                    | Pass        |

Notes:

- Duplicate organisations or imports:
- Errors or unexpected behaviour:
- Worker restarted and source re-enabled after testing:

### Database corroboration — 17 September 2026

Read-only hosted inspection corroborated the three recorded outcomes:

- `d19e3c07-867b-40ef-b0e0-ec28d57674bd`: complete, run **11**, one attempt,
  six accepted records and zero quarantine.
- `d04b0c07-2d28-4482-a346-b25de104c7ea`: cancelled, zero attempts and no staged run.
- `1aa2064f-bbe2-40fe-8472-7433e92ba442`: complete, run **12**, one attempt,
  six accepted records and zero quarantine.

The ACNC source is enabled and its schedule interval remains null (Off). These
checks close the operator queue/restart, source-pause and re-enable scenarios.
They do not test interruption after a worker has claimed a job: both successful
jobs completed on their first attempt. The separate disposable-database tests
below now supply that evidence. The operator's notes above remain unchanged;
no unrecorded observations have been inferred.

## Controlled recovery results — 17 September 2026

**All four requested recovery scenarios passed.** Results are also recorded in
[the machine-readable validation report](acquisition-recovery-validation.json).
The test used newly created PostgreSQL 16 and worker containers on an internal-only
Docker network. HTTP responses were synthetic fixtures, the worker used the
restricted LOGIN migration, and no live credentials or production containers were
used. The existing ingestion SQL suites ran successfully in the same database.

| Scenario                           | Observed result                                                                                                                                                                                                                                                                                                                        | Outcome |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| Process killed during pagination   | Worker reached the second-page request after processing page one, then received SIGKILL (exit 137). Replacement was idle while the original lease was valid. After test-only lease expiry, attempt 2 fetched a complete fresh acquisition and staged exactly one run. Old token rejected.                                              | Pass    |
| Process killed after checkpoint    | Worker received SIGKILL after its checkpoint transaction committed. Attempt 2 reused the identical envelope and observation time, made no source requests, and staged exactly one run. Old token rejected.                                                                                                                             | Pass    |
| Protected human edit               | Published synthetic records, corrected a name manually, then acquired changed source data through the worker. Review showed a protected conflict; the human correction and original identity links remained intact.                                                                                                                    | Pass    |
| Withdrawal survives refresh/replay | Suppressed a website and withdrew the second organisation before a changed-data refresh. Anonymous reads did not return the website or withdrawn organisation. Existing reprocessing suites also passed suppression/whole-record withdrawal replay checks.                                                                             | Pass    |
| Failed and partial source          | A pre-acquisition failure retained a failed run with zero records. A page-two failure retained a partial run with one new record. Public state and previous versions were preserved. An otherwise eligible name approval was rejected specifically with `Complete enabled source required`; neither incomplete run gained an approval. | Pass    |

Lease expiry was advanced **only in the disposable database** after killing the
processes. The tests exercise actual process death, PostgreSQL transactions,
restart/checkpoint behaviour and token rejection, but do not wait five real minutes
or simulate a physical power failure of AKHOME. PostgreSQL auth helpers emulate
application JWTs; hosted sign-in behaviour is supported by the operator checks.

To repeat from the repository root (Docker must be running):

```sh
# Only needed if the local worker image is missing.
docker build -t community-orgs-acquisition:local \
  -f tools/ingestion/deploy/Dockerfile tools/ingestion

python3 scripts/test-acquisition-recovery.py
```

The runner mounts the current Python source read-only, uses fixture-only transport,
creates its own network/database/worker containers and removes them on exit. It
does not accept a database URL or load the AKHOME credential directory. The live
worker was left running; acquisition scheduling was not changed.

This closes the requested recovery checks. The next operational decision is the
pilot refresh cadence, followed by observing its first scheduled job. Scheduling
remains Off until explicitly enabled. Broader P27 complete-snapshot reconciliation
and closure semantics are separate work; these tests do not establish that missing
records in filtered CKAN results mean an organisation has closed.
