# Community Organisations Portal

A web application for maintaining a shared directory of community organisations, charities, and not-for-profit groups. It brings organisation profiles, contacts, legal records, finances, operations, partnerships, and history together in one place.

The project uses Australian terminology and includes fields for ABN, ACN, ACNC registration, incorporation, and deductible gift recipient (DGR) endorsement. The research notes include community organisations in the Snowy Valleys region.

## Current features

- **Organisation directory:** paginated listings, public/private profiles, descriptions, establishment dates, and business or trading names.
- **Contact and legal records:** contact details, addresses, registration and endorsement information, and links to supporting documents.
- **Financial records:** annual budgets, financial year dates, funding sources, and audit information.
- **Operations:** staffing, service areas, accessibility, languages, and locations displayed on a MapLibre map using MapTiler tiles.
- **Relationships and history:** partner organisations, relationship dates, timelines, and historical milestones.
- **Authentication:** email/password, email links, password recovery, guest browsing, and OAuth entry points for GitHub, Google, Microsoft, and Discord.
- **Account security:** authenticator-app MFA enrolment and verification.

The `/admin` and `/reports` routes exist but currently display placeholder pages. The admin route has an access check; a role-management interface and reporting tools are not yet implemented there.

## Technology

| Area                    | Implementation                                         |
| ----------------------- | ------------------------------------------------------ |
| Application             | SvelteKit 2, Svelte 5, TypeScript, Vite                |
| UI                      | Skeleton UI 5.0.1, Tailwind CSS 4, Lucide icons        |
| Data and authentication | Supabase PostgreSQL, Auth, and SSR cookie sessions     |
| Validation              | Zod schemas and server-side form actions               |
| Maps and visualisations | MapLibre GL, MapTiler, D3                              |
| Deployment              | SvelteKit Vercel adapter and a scheduled cron endpoint |

The application data lives in the **`community_orgs` PostgreSQL schema**. Both browser and request-scoped Supabase clients explicitly select this schema.

## Getting started

### Requirements

- Node.js **22.20+ within the 22.x line**, with npm. The lockfile includes Supabase packages requiring Node 22 and a native dependency requiring at least 22.20 on that line.
- Access to a configured Supabase project, or a local Supabase stack.
- A MapTiler key to display map tiles.
- Python 3.10+ only if refreshing the local Skeleton documentation.
- Supabase CLI and a Docker-compatible container runtime only if running Supabase locally.

### Configure the application

Select the project Node version and install the locked dependencies:

```bash
nvm install
nvm use
npm ci
```

Create `.env.local` using the application section of [`.env.example`](.env.example). Replace the placeholders with values for your environment:

```dotenv
PUBLIC_SUPABASE_URL=https://your-project.supabase.co
PUBLIC_SUPABASE_ANON_KEY=your-anon-key
PRIVATE_SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
CRON_SECRET=your-long-random-secret
PUBLIC_MAPTILER_KEY=your-maptiler-key
PUBLIC_TURNSTILE_SITE_KEY=your-turnstile-site-key
```

| Variable                            | Purpose                                                           |
| ----------------------------------- | ----------------------------------------------------------------- |
| `PUBLIC_SUPABASE_URL`               | Supabase API and Auth endpoint                                    |
| `PUBLIC_SUPABASE_ANON_KEY`          | Browser API key; database policies determine access               |
| `PRIVATE_SUPABASE_SERVICE_ROLE_KEY` | Server-only client used by the cron route; imported at build time |
| `CRON_SECRET`                       | Bearer token required by `/api/cron`                              |
| `PUBLIC_MAPTILER_KEY`               | Map tile access; maps need this at runtime                        |
| `PUBLIC_TURNSTILE_SITE_KEY`         | CAPTCHA widget used by authentication forms                       |

Keep service-role keys and other secrets out of browser code and version control. Environment files are ignored by Git; `.env.example` is the tracked template.

The template also documents separate credentials for Supabase Auth and developer tools. OAuth secrets and the Turnstile secret belong in the Supabase configuration, not in `PUBLIC_` variables. MCP access tokens are developer-tool credentials and are not required by the application.

### Configure Supabase

For a hosted project:

1. Apply the SQL migrations in [`supabase/migrations`](supabase/migrations) in version order, using your migration tooling. Check the project's existing migration history before applying the baseline to an existing database.
2. Expose `community_orgs` through the Data API.
3. Configure the Auth site URL and allowed redirects for your application origin.
4. Configure the OAuth providers you intend to use. The application's provider list is in [`src/lib/auth/providers.ts`](src/lib/auth/providers.ts).
5. Configure Turnstile, anonymous sign-ins, email confirmation, and TOTP MFA to match the flows you enable. [`supabase/config.toml`](supabase/config.toml) records the local settings.
6. Use the email templates in [`supabase/templates`](supabase/templates) for the application's confirmation, email-link, recovery, and email-change flows.

OAuth providers return to Supabase's `/auth/v1/callback` endpoint. Supabase then returns to the application; the app handles OAuth at `/auth/callback` and email verification at `/auth/confirm`.

For local development, configure the Auth environment variables described in `.env.example` before starting the stack. The checked-in configuration enables all four OAuth providers and Turnstile; supply their settings or disable unused providers in your local configuration.

```bash
supabase start
supabase status
```

Use the URL and keys reported by `supabase status` in `.env.local`. The configured local services are:

| Service          | Address                  |
| ---------------- | ------------------------ |
| Supabase API     | `http://127.0.0.1:54511` |
| PostgreSQL       | `127.0.0.1:54512`        |
| Supabase Studio  | `http://127.0.0.1:54513` |
| Test email inbox | `http://127.0.0.1:54514` |

The local database configuration targets PostgreSQL 17. `supabase db reset` rebuilds the local database from migrations and **deletes existing local data**. The configuration references `supabase/seed.sql`, but no seed file is currently included.

### Run the development server

```bash
npm run dev -- --open
```

The local Auth configuration allows `localhost:5173` and `127.0.0.1:5173`. Update the allowed redirects if you use a different origin.

## Access model

Application hooks validate sessions, and server-side helpers check organisation permissions. PostgreSQL row-level security independently restricts direct Data API access.

| Caller                           | Access                                                                              |
| -------------------------------- | ----------------------------------------------------------------------------------- |
| Visitor without a session        | Landing and authentication pages; protected application routes require sign-in      |
| Guest session                    | Public organisation browsing; sensitive tables and writes are restricted            |
| Registered user                  | Public organisation records and private organisations they are authorised to access |
| Organisation member or moderator | Organisation read access; levels 1 and 2 do not satisfy the editor check            |
| Organisation admin or owner      | Organisation editing at levels 3 and 4; qualifies for the `/admin` route            |

Creating an organisation grants its creator the owner role through a database trigger. Roles are scoped to organisations; there is no separate site-wide administrator role in the application's access model.

Sensitive-table restrictions cover contact, financial, legal, document, governance, membership, and role records. For registered users, the existing organisation policies still determine visibility: registering does not grant access to every private organisation. Sensitive records attached to public organisations can be visible to registered users.

Users with a verified MFA factor must satisfy the second factor for table access. The role-management RPCs also enforce MFA explicitly because their `SECURITY DEFINER` execution bypasses table policies. Guest and unauthenticated callers cannot use those role-management RPCs.

See [`src/hooks.server.ts`](src/hooks.server.ts), [`src/lib/server/authorization.ts`](src/lib/server/authorization.ts), and the SQL migrations for the implemented rules.

## Development commands

| Command                      | Purpose                                                             |
| ---------------------------- | ------------------------------------------------------------------- |
| `npm run dev`                | Start the development server                                        |
| `npm run build`              | Build the application with the Vercel adapter                       |
| `npm run preview`            | Preview the production build locally                                |
| `npm run check`              | Generate SvelteKit types and run Svelte/TypeScript checks           |
| `npm run check:watch`        | Run type checks in watch mode                                       |
| `npm run lint`               | Check formatting, then run ESLint                                   |
| `npm run format`             | Format the repository                                               |
| `npm run test:providers`     | Check provider contracts and the limited local proof adapter        |
| `npm run test:fleet`         | Check fleet inventory, capability and audit contracts               |
| `npm run update-db-types`    | Regenerate `src/lib/db.types.ts` from the configured hosted project |
| `npm run docs:skeleton:sync` | Refresh the official Skeleton v5 Svelte documentation snapshot      |

The database-type command currently contains a project-specific ID in `package.json`. Update it before generating types against another project.

### Database regression checks

SQL regression scripts cover sensitive reads, MFA checks on role-management RPCs, and the admin lookup:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/p1_access_regression.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/p2_admin_access_regression.sql
```

Set `DATABASE_URL` to the database you intend to test and connect as `postgres`. These scripts create fixtures, exercise API roles, assert expected results, and roll back their changes. They can also be run through Supabase SQL tooling. Run `npm run test:cron` to check the actual cron handler with mocked database responses (application environment variables must be configured). There is currently no browser-test command.

## Project layout

```text
src/
  routes/                 SvelteKit pages, server loads, actions, and endpoints
    organisations/[id]/   Profile, contact, legal, finance, operations,
                          relationships, and history sections
    auth/                 Sign-in, registration, callbacks, recovery, and MFA
    account/security/     Authenticator management
    admin/                Protected placeholder page
    reports/              Placeholder page
    api/cron/             Authenticated health check and guest cleanup
  components/             Forms, tables, navigation, maps, and visualisations
  lib/
    auth/                 Auth schemas, providers, CAPTCHA, and session helpers
    server/               Authorization, provider ports, validation, and redirects
    db.types.ts           Generated database types
  hooks.server.ts         Request-scoped Supabase client and access guards
supabase/
  migrations/             Database schema, functions, grants, and RLS policies
  templates/              Auth email templates
  tests/                  Transactional SQL regression checks
scripts/                  Documentation refresh tooling
docs/                     Domain notes, design material, and library references
static/                   Icons and images
```

## Deployment and scheduled maintenance

The project uses `@sveltejs/adapter-vercel`. Set the application environment variables in the deployment environment before building, and configure Supabase Auth redirects for the deployed origin.

`package.json` requires Node `^22.20.0`, `.nvmrc` selects the 22.x line, and `svelte.config.js` targets `nodejs22.x`. The Vercel project setting is also 22.x. The package engine range keeps future Vercel builds on Node 22.

[`vercel.json`](vercel.json) schedules `/api/cron` daily at **00:00 UTC**. The endpoint requires `Authorization: Bearer <CRON_SECRET>` and uses the service-role key to:

1. Call `public.health_check()`.
2. Purge anonymous accounts older than 30 days through `community_orgs.purge_stale_anonymous_users()`.

The health-check function is not defined in the tracked migrations and must exist in the target environment. Cleanup runs only after a successful health check. Either stage failing returns HTTP 500, while a completed run returns HTTP 200 and logs the completion time and number of anonymous accounts removed.

## Documentation

The `docs/` folder contains domain research and earlier implementation proposals as well as current references. Some examples use outdated column names, paths, or access models. Use the current source and migrations as the authority for implemented behaviour.

| Topic                  | References                                                                                                                                        |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Organisation records   | [Organisations](docs/organisations.md), [contacts](docs/contact.md), [legal](docs/legal.md), [finance](docs/finance.md)                           |
| Activities and history | [Operations](docs/operations.md), [relationships](docs/relationships.md), [history](docs/history.md)                                              |
| Data and access design | [Organisation IDs](docs/org_id_relationships.md), [roles](docs/roles.md), [access control](docs/access_control.md), [ABAC proposal](docs/ABAC.md) |
| Research               | [Community organisation notes](docs/Content.md)                                                                                                   |
| Skeleton UI            | [Local Svelte index](docs/vendor/skeleton/index.md), [LLM index](docs/vendor/skeleton/llms.txt)                                                   |

The Skeleton snapshot comes from the official documentation and tracks rolling v5, not an exact 5.0.1 snapshot. Its manifest records source URLs, fetch time, and page hashes. Refresh it with `npm run docs:skeleton:sync`; all links in the local Svelte index point to downloaded Markdown pages, while links within page bodies may refer back to the official site.
