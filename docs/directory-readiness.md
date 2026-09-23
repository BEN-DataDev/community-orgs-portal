# Directory readiness (P32)

Status: implemented and deployed on 22 September 2026. Hosted migration
`20260922052255_directory_readiness` is recorded in the linked Supabase project and
Vercel production deployment `dpl_EgFjYVd54bVPvR25NwufmR365UhN` is live.

P32 makes the directory usable before registry-derived publication increases its
size. It adds server-side search and narrows the correction gaps for existing
aliases, locations, document links and relationships.

## Directory search

Migration
[`20260922020000_directory_readiness.sql`](../supabase/migrations/20260922020000_directory_readiness.sql)
adds `community_orgs.search_organisations(query, offset, limit)` and supporting
indexes.

The search contract is:

- case-insensitive partial matching for organisation names and aliases;
- exact ABN matching after punctuation and spaces are removed for registered users
  who can read legal details;
- exact ABN, exact entity name and exact alias matches rank ahead of partial
  matches;
- stable ordering by relevance, entity name and organisation UUID;
- server-side count, offset and bounded page size; and
- the same visibility boundary as ordinary reads through `can_view_org`, including
  public access and member-visible private organisations.

The function is `SECURITY INVOKER`, so organisation and child-table RLS continues
to apply to every search and returned field. Anonymous users can search public
names and aliases but cannot search or receive protected ABNs or contact details.
Registered users can search exact ABNs where their ordinary legal-detail access
permits it. Only `anon` and `authenticated` can execute the read-only function.

The organisations page now accepts `q`, preserves it through pagination, and
renders a native GET search form that works without client JavaScript. Empty
queries retain the alphabetical directory.

## Correction workflows

Editors can now update existing:

- business and trading aliases from the organisation overview;
- location name, address, type and coordinates;
- document name and URL; and
- relationship partner text, type, start date and end date.

Every action rechecks editor access server-side, validates the record UUID and
editable fields, scopes the update by both record ID and route organisation ID,
and updates audit columns from the authenticated session. A UUID belonging to
another organisation therefore updates no row and is reported as a failure.

Relationship end dates cannot precede their start dates. The current text-based
`partner_org` model is retained; replacing it with a linked organisation identity
is a separate model decision.

### Hosted signed-in browser findings

A production editor regression on 22 September 2026 found:

- business/trading names can be added and edited; scoped removal was added locally
  on 22 September after this hosted regression and awaits deployment verification;
- locations can be added, edited and removed successfully;
- documents are URL records only; local file selection and upload are not
  implemented; and
- relationships can be added and edited; scoped removal was added locally on
  22 September after this hosted regression and awaits deployment verification.

Alias and relationship removal actions now recheck editor access and scope deletion
by both record and organisation IDs; the local regression covers success,
cross-organisation denial and editor authorization. Hosted verification remains.
Local document upload is a separate storage, access and retention capability rather
than a failure of the implemented document-link workflow.

## Validation

Validation completed locally:

- `npm run check`: zero Svelte/TypeScript diagnostics;
- `npm run build`: production build passed (existing Rollup source-map, chunk-size
  and optional Sharp adapter warnings remain warnings);
- ESLint passed for every changed TypeScript/Svelte file;
- Markdown/TypeScript/Svelte formatting and `git diff --check` passed; and
- [`directory_readiness.sql`](../supabase/tests/directory_readiness.sql) passed on
  PostgreSQL 17 in a disposable database.

The SQL regression covers public results, alias search, anonymous legal/contact
denial, registered-user punctuation-normalised exact ABN search, rejection of
partial ABNs, stable server pagination counts, anonymous private-row denial,
member-visible private results, input limits, function grants and all three search
indexes.

Hosted verification confirmed all three indexes, invoker rights, anonymous and
authenticated execution, anonymous denial of legal/contact child rows, registered
exact-ABN search and successful public directory/search responses. The production
build passed with the existing source-map, chunk-size and optional Sharp warnings.
The signed-in editor regression passed location add/edit/remove and alias and
relationship add/edit, while identifying the two missing removal actions and the
separate document-upload gap recorded above. With P31 and P32 deployed, P33 is
complete; P34a staged-validation resolution and the P34b NSW adapter are the next
implementation tracks alongside these P32 follow-ups.
