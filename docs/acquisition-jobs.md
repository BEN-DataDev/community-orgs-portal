# ACNC acquisition jobs

Updated 17 September 2026: the acquisition migration and restricted worker LOGIN
are deployed to Supabase project `gqltsfijginclwszrcfj`. The worker is installed
and running on **AKHOME** in Docker Desktop. Password authentication, verified TLS
and queue processing succeeded. The first manual live refresh completed as
**run 9**, with six accepted records and zero quarantine. The postcode 2730 pilot
is configured with scheduling off. The portal changes are now live on Vercel.

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
  and no schedule. Its audit event identifies a user-authorised management-API
  operation; no browser session or MFA session was impersonated.
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
  unauthenticated cron request returned 401. Signed-in browser form submission
  remains an operator check; the successful manual run used the management API.
- Open [Acquisition jobs](https://community-orgs-portal.vercel.app/admin/ingestion/jobs)
  or [review run 9](https://community-orgs-portal.vercel.app/admin/ingestion?run=9)
  after signing in. No second import or publication was triggered by deployment.
- This was a working-tree deployment. Git changes remain uncommitted; a future
  Git-triggered deployment must include these changes to preserve this release.


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
A platform administrator configures an existing live ACNC resource with one
four-digit postcode, the exact reviewed CKAN licence title and a schedule. The
initial schedule is **Off**. Source approval remains managed in `/admin/sources`.

An ingestion operator can select **Run acquisition** when the source is enabled
and configured. Repeated submissions reuse the existing active job. The page
shows the latest 50 jobs, attempts, availability, lease expiry and completion,
with a link to the staged import. **Refresh status** reloads these details.
Complete imports still need the existing match/review/approval/publication steps.
Partial and failed acquisitions retain their evidence and block publication.

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
5. Configure the pilot postcode and licence in the UI, leave scheduling off, and
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
qualification across resource releases, hosted worker measurements and the live
second-cycle/browser release checks remain outstanding. P26 application/worker code is implemented and its database migration is deployed;
worker hosting, database connectivity and a six-record live refresh are verified
on AKHOME. The production portal is deployed and public/protected-route HTTP
checks passed. Signed-in form checks and the remaining P27/P30 release scenarios
are still outstanding.
