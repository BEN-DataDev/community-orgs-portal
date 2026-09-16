# Documentation-to-code gap analysis

Reviewed: 15 September 2026.

## Summary

The portal implements the main organisation register and the contact, legal,
finance, operations, history and organisation-specific relationship pages.
The largest missing areas are role-management screens, relationship browsing and
editing, and screens for several domains already represented in the database.

The documents mix earlier implementation proposals, schema descriptions, research
notes and current feature documentation. An old example is not automatically an
approved requirement. Several differences require a product or data-model decision
before implementation, particularly ABAC, linked partner organisations and financial
reporting. Current source and migrations remain authoritative, as stated in the
[README](../README.md#documentation).

### Suggested order of work

1. Fix the UUID mismatch in relationship partner search and verify creation in a browser.
2. Add role assignment/request management using the existing database model and RPCs.
3. Add relationship editing and decide whether partners should be linked records.
4. Complete editing for aliases, locations and document links.
5. Add the missing domain screens and fields according to product priorities.
6. Update or archive obsolete examples so they no longer imply a different implementation.

These priorities are recommendations from this review, not an existing project roadmap.

## Scope and method

Reviewed all 19 project Markdown documents directly under `docs/`, comparing their
features and examples with routes, components, validation, server helpers, generated
database types, checked-in migrations and relevant tests.

The generated `docs/vendor/skeleton/` tree is library reference material. Its index
and version caveat were checked; its component catalogue is not a list of features
the portal needs to implement. The project uses Skeleton 5.0.1, while the snapshot
tracks rolling upstream v5.

This is a repository review. It does not establish which migrations are deployed,
which research records are in a live database, or whether external services are
configured correctly. No production data or external configuration was changed.
Absence findings mean no implementation was found in the checked-in application
and migrations reviewed here.

Status meanings:

- **Implemented:** the documented capability has corresponding application code.
- **Partial:** part of the capability exists, with an identifiable missing workflow.
- **Missing:** no corresponding application feature was found.
- **Different model:** the code intentionally or effectively uses another representation;
  the discrepancy needs reconciliation rather than copying the example.
- **Reference / unverified:** development or research material, or a claim requiring
  external verification.

## Document coverage

| Document                                           | Assessment                       | Main finding                                                                                                                                                             |
| -------------------------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [organisations.md](organisations.md)               | Mostly implemented / partial     | Listing, pagination, creation, overview and basic editing exist. Role UI and existing trading-name editing are absent.                                                   |
| [contact.md](contact.md)                           | Implemented with different model | Email, primary phone, website and addresses are editable. Addresses are free-text physical/postal fields rather than separate street/city/state/postcode/country fields. |
| [legal.md](legal.md)                               | Mostly implemented / partial     | Legal details and document links exist; existing document links cannot be edited. Generic tax/charity/registration fields have been replaced by more specific fields.    |
| [finance.md](finance.md)                           | Partial / different model        | Budget, year-end date, audit date and funding-source names exist. Revenue and funding percentages do not.                                                                |
| [operations.md](operations.md)                     | Partial / different model        | Staffing, hours, reach, location creation/removal and map exist. Location editing and automatic geocoding are absent; service area is one text value.                    |
| [history.md](history.md)                           | Mostly implemented               | History entries can be added and displayed. Last-editor names shown in the proposal are absent.                                                                          |
| [relationships.md](relationships.md)               | Largely missing                  | No global relationship list, individual detail route or relationship editing workflow. Organisation-specific listing/creation exists elsewhere.                          |
| [org_id_relationships.md](org_id_relationships.md) | Partial / different model        | Partner picker and timeline exist, but partners are saved by name, with no partner foreign key or description field. UUID conversion affects search.                     |
| [roles.md](roles.md)                               | Missing UI / different model     | No role page or RoleBuilder. Existing role tables and RPCs differ from the proposed per-organisation role definitions.                                                   |
| [access_control.md](access_control.md)             | Different model                  | Access control exists through roles, server guards and RLS; the proposed owners/access/role-definitions tables are not the implemented architecture.                     |
| [ABAC.md](ABAC.md)                                 | Proposal not implemented         | No attribute-policy engine, policy-builder UI or ABAC token claims found. Existing role hierarchy, expiry and audit mechanisms cover only some related concepts.         |
| [thumbnail.md](thumbnail.md)                       | Schema reference with gaps       | Describes the database, not thumbnail images. Five domain tables have no portal screens; some fields in otherwise implemented areas also lack UI.                        |
| [structure.md](structure.md)                       | Outdated structure / partial     | Current paths and component organisation differ. Admin and Reports routes exist but are placeholders.                                                                    |
| [formatters.md](formatters.md)                     | Implemented                      | All six documented formatter functions exist.                                                                                                                            |
| [Content.md](Content.md)                           | Research / unverified            | No import pipeline tied to these notes found. Live record coverage was not checked.                                                                                      |
| [MCP_SETUP_GUIDE.md](MCP_SETUP_GUIDE.md)           | Outdated development reference   | Both configuration files exist, but actual server transports and commands differ from the guide.                                                                         |
| [avatars.md](avatars.md)                           | Implemented; local tests pass    | Settings actions, image handling, private storage support and cleanup correspond to the document. Live storage policies were not retested.                               |
| [email-changes.md](email-changes.md)               | Implemented; local tests pass    | Request/resend and confirmation flows exist. Hosted settings and real delivery remain external verification items.                                                       |
| [account-sessions.md](account-sessions.md)         | Implemented; local tests pass    | Session listing, individual revocation and bulk logout exist. Live Auth database behaviour was not retested.                                                             |

## Detailed gaps

### G01 — Relationship search still treats UUIDs as numbers

**Priority: high. Type: implementation defect identified in source.**

The [relationship page](../src/routes/organisations/[id]/relationships/+page.svelte)
passes `Number(page.params.id)` into the form. Organisation IDs are UUID strings.
Both [RelationshipForm](../src/components/forms/RelationshipForm.svelte) and
[OrganisationSearch](../src/components/common/OrganisationSearch.svelte) still
type the exclusion ID as a number. For a normal UUID, this produces `NaN`, which
the search component includes in `org_id=not.in.(NaN)`.

This is incompatible with the UUID column and is expected to make partner lookup
fail. The component does not present the query error to the user. The server action
itself correctly obtains the organisation UUID from route parameters; the defect
is in the picker path. This was not reproduced against a live database in this review.

**Completion:** preserve strings through the page, form and search; verify search
returns another organisation and excludes the current one; surface lookup failures;
verify relationship creation end to end.

### G02 — Role management has a backend but no usable portal workflow

**Priority: high. Type: missing UI plus model decision.**

[roles.md](roles.md) proposes creating/deleting custom organisation roles and a
permission editor. [organisations.md](organisations.md) links to a roles page.
Neither that route nor `RoleBuilder` exists. The [Admin page](../src/routes/admin/+page.svelte)
only says “Nothing here yet.”

The implemented model has `roles`, `user_organisation_roles`, `role_requests` and
`role_audit_log`, with grant, revoke, request and review RPCs. See the
[baseline schema](../supabase/migrations/20260101000000_baseline_community_orgs_schema.sql)
and [role RPC hardening](../supabase/migrations/20260914071835_fix_p1_sensitive_reads_and_role_rpc_mfa.sql).
These RPCs have no corresponding application management screens/actions.

**Completion:** expose membership/role assignment and request review using the
existing authorized RPCs. Separately decide whether custom per-organisation role
definitions are wanted: current `roles` do not have the proposal's `org_id` scope.
Do not implement the old `role_definitions` example unchanged.

### G03 — Relationships lack global browsing, details and editing

**Priority: medium. Type: missing workflow.**

[relationships.md](relationships.md) describes a paginated `/relationships` list,
individual `/relationships/[id]` details, metadata and an edit form. Those routes
are absent. Only [organisation-specific relationships](../src/routes/organisations/[id]/relationships/+page.svelte)
and the overview summary exist. The [server actions](../src/routes/organisations/[id]/relationships/+page.server.ts)
only create relationships.

An existing relationship cannot be corrected or ended through the UI after
creation. The proposed free-text partner input is also absent: the current creation
form requires selecting a registered organisation. Whether external partners should
be allowed needs a decision.

**Completion:** add authorized editing, including end dates; decide whether global
browsing and separate detail URLs are still needed; include the intended metadata.
Relationship deletion would be an additional requirement, not one clearly specified
by this document.

### G04 — Partner identity and descriptions differ from the relationship proposal

**Priority: medium. Type: data-model decision.**

[org_id_relationships.md](org_id_relationships.md) proposes `partner_org_id`, a joined
partner record and a relationship description. The current schema stores
`partner_org` as plain text. The picker copies the entity name; it does not persist
the selected UUID. There is no relationship description column/form field/schema
entry. See [RelationshipForm](../src/components/forms/RelationshipForm.svelte),
[validation](../src/lib/server/validation.ts) and the baseline `relationships` table.

Consequently, partner names do not automatically follow organisation renames and
cannot reliably identify a particular organisation when names collide. Search uses
`entity_name` only; the document also proposes trading-name search/display.

**Completion:** decide between free-text partners, linked partners or both. A linked
model requires a migration, matching/backfilling existing names, access rules and
updated queries. Add descriptions and alias search if retained as requirements.

### G05 — Existing aliases, locations and document links cannot be edited

**Priority: medium. Type: partial workflows.**

| Area                 | Present                              | Missing relative to the examples                                          | Evidence                                                                                                                                            |
| -------------------- | ------------------------------------ | ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Trading names        | Add alias; display trading names     | Change an existing trading name; include one during organisation creation | [Overview actions](../src/routes/organisations/[id]/+page.server.ts), [organisation form](../src/components/forms/OrganisationForm.svelte)          |
| Locations            | List, add, remove; store coordinates | Edit an existing location's name, address or type                         | [Operations page](../src/routes/organisations/[id]/operations/+page.svelte), [actions](../src/routes/organisations/[id]/operations/+page.server.ts) |
| Legal document links | List, open, add, remove              | Edit an existing document name or URL                                     | [Legal page](../src/routes/organisations/[id]/legal/+page.svelte), [actions](../src/routes/organisations/[id]/legal/+page.server.ts)                |

Business-name aliases can be added but the overview renders only aliases of type
`Trading Name`. There is no alias removal action either; removal is a useful
follow-on rather than an explicit feature of the original document.

The legal proposal uses URLs, not uploaded files. File upload/storage for legal
documents should not be counted as a missing requirement from `legal.md`.

### G06 — Five database domains have no portal screens

**Priority: medium, subject to product scope. Type: schema-only capabilities.**

[thumbnail.md](thumbnail.md) describes these areas, all present in the
[baseline schema](../supabase/migrations/20260101000000_baseline_community_orgs_schema.sql):

| Domain                | Documented capability                               | Current application                   |
| --------------------- | --------------------------------------------------- | ------------------------------------- |
| Governance            | Board structure, constitution, organisational chart | Loaded by overview; no display/editor |
| Programs and services | Offerings, descriptions, fees                       | Loaded by overview; no display/editor |
| Accreditation         | Certifications/accreditations                       | Loaded by overview; no display/editor |
| Resources and assets  | Asset/resource records                              | Loaded by overview; no display/editor |
| Performance metrics   | Indicators and values over time                     | No domain query or screen found       |

The first four are fetched in the [overview loader](../src/routes/organisations/[id]/+page.server.ts)
but unused by the overview UI. This is not equivalent to implemented features.
`organisations.md` itself leaves the additional display/form sections as comments.

**Completion:** define read/edit workflows and visibility for each domain, then add
pages and validated actions. These documents are not detailed enough to determine
the full acceptance criteria for those screens.

### G07 — Social media, insurance and auditor details have no UI

**Priority: medium. Type: fields supported below the UI.**

[thumbnail.md](thumbnail.md) mentions all three. The database columns and optional
JSON validation fields exist, but current forms and pages do not render them:

- `contact_info.social_media`: absent from [ContactForm](../src/components/forms/ContactForm.svelte).
- `legal_details.insurance_details`: absent from [LegalForm](../src/components/forms/LegalForm.svelte).
- `financial_info.auditor_details`: absent from [FinancialForm](../src/components/forms/FinancialForm.svelte).

See [validation.ts](../src/lib/server/validation.ts). These are not missing database
tables: the remaining work is defining structured user inputs and displays.

### G08 — Finance is narrower than the proposed financial reporting

**Priority: decision needed. Type: missing information plus different model.**

[finance.md](finance.md) proposes annual revenue, a financial-year label,
funding-source percentages, tax status and DGR status. The implemented
[finance page](../src/routes/organisations/[id]/finance/+page.svelte) and form use:

- Annual **budget**, which is not equivalent to actual revenue.
- A financial-year **end date**, rather than a year label.
- A text array of funding-source names, with no percentages.
- Last audit date.

DGR endorsement and concession information are handled in Legal. They should not
be counted as wholly absent, but the old generic tax-status selector has no exact
equivalent. The old `annual_revenue` and percentage object structure are not in the
current financial schema.

**Completion:** agree which financial measures are required. Revenue and funding
shares need a schema change as well as UI work; moving or renaming budget does not
satisfy a revenue requirement.

### G09 — Operations omits geocoding and structured multiple service areas

**Priority: decision needed. Type: partial / different model.**

[operations.md](operations.md) geocodes addresses automatically and lets users add
multiple service-area tags. [OperationsMap](../src/components/maps/OperationsMap.svelte)
instead uses stored latitude/longitude, and the page explains when a location lacks
coordinates. The current operations form uses one `service_area` text field.

Staff counts, operating hours, markers and map bounds are implemented. Current
operations additionally exposes demographics, supported languages and accessibility.
The map key is `PUBLIC_MAPTILER_KEY`, not the example's `VITE_MAPTILER_KEY`.

**Completion:** decide whether automatic address lookup and independently editable
service areas are required. Map rendering is already present; an unconfigured map
key alone is not an implementation gap.

### G10 — History omits last-editor identity

**Priority: low. Type: display gap.**

[history.md](history.md) displays “Last edited by [name] on [date]”. The current
[history page](../src/routes/organisations/[id]/history/+page.svelte) only displays
the date. Server-side audit columns are written, so attribution storage and
attribution display must be distinguished.

The core add/list workflow, founding members, milestones and structural changes
exist. Neither the current UI nor the proposal clearly provides a complete workflow
for editing/deleting an existing history entry; that should be specified separately.

### G11 — ABAC is an alternative architecture proposal

**Priority: architecture decision, not an automatic implementation backlog.**

[ABAC.md](ABAC.md) proposes attribute-based access control: decisions based on
subject, resource, action and environmental attributes. The following proposal
families have no matching application/database implementation found:

| Proposal family            | Missing elements                                                                                                                    |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Policy engine              | Attribute tables, access policies/logs, `check_access_policy`, attribute-maintenance triggers and attribute-based discovery queries |
| Contextual rules           | Region, clearance, staff-size, language, workflow/team and scheduled-access evaluation                                              |
| Management UI              | Permission editor, custom role builder, access scheduler and effective-permission screens                                           |
| Operational tooling        | Permission cache/observer/aggregator, permission metrics, audit viewer, anomaly detection and compliance reporting                  |
| Visual policy tools        | Flow/rule builders, simulator, flow persistence/versioning and evaluation engines                                                   |
| Authentication integration | Proposed `custom_access_token_hook` that injects ABAC claims                                                                        |

The existing [authorization helper](../src/lib/server/authorization.ts), role/RLS
migrations and cron code implement a role-based model with hierarchy, role expiry
and role audit records. Those overlap with some concepts but are not the proposed
general ABAC engine. The older [access_control.md](access_control.md) owners/access
tables are also superseded by the implemented model.

**Completion:** first decide whether to retain role-based access, extend it with
specific conditions, or undertake an ABAC migration. The proposal contains evolving
examples and references to other helpers; it is not a ready-to-run migration set.

### G12 — Reports and Admin are placeholders

**Priority: medium once requirements are defined. Type: scaffold only.**

[structure.md](structure.md) lists these routes; both exist. Their loaders return
empty objects and their pages show “Nothing here yet.” See [Reports](../src/routes/reports/+page.svelte)
and [Admin](../src/routes/admin/+page.svelte).

The structure document does not specify the reports, filters, exports or admin
operations. The ABAC proposal's reporting/dashboard examples are not implemented
by the existence of these routes. Define their scope before treating them as
independent feature tickets.

## Documentation reconciliation

These differences should normally be resolved in documentation rather than by
restoring obsolete code:

| Document(s)                                | Correction needed                                                                                                                                                                                                                |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `thumbnail.md`                             | Replace “12 tables” and auto-incrementing keys with the actual expanded schema and UUID-based domain IDs. Explain `entity_name` and aliases. The filename refers to a schema overview, not image thumbnails.                     |
| `structure.md`                             | Components live in `src/components`, not `src/lib/components`; routes use `organisations`; creation is inline. Missing generic Card/Button/store files are not inherently missing user features.                                 |
| Organisation/domain examples               | Replace `legal_name`, `trading_name`, integer IDs, global Supabase imports and old event/component APIs with current equivalents.                                                                                                |
| `contact.md`                               | Document physical/postal address text and primary phone JSON. Separate address fields would be a new data-model choice.                                                                                                          |
| `legal.md`                                 | Document ABN, incorporation, ACNC and concession fields and the separate documents table. Old generic registration/charity/tax fields do not map one-to-one.                                                                     |
| `roles.md`, `access_control.md`, `ABAC.md` | Clearly label proposals and distinguish them from the current role hierarchy and RLS.                                                                                                                                            |
| `MCP_SETUP_GUIDE.md`                       | Actual `.mcp.json` and `.vscode/mcp.json` use HTTP for Supabase and `npx` for Svelte, with additional servers. Update examples accordingly. Both configuration files and secret-ignore rules exist; connectivity was not tested. |

[formatters.md](formatters.md) matches the six functions in
[formatters.ts](../src/lib/utils/formatters.ts): date, time, currency, phone, ABN
and mobile formatting. Their existence does not mean every applicable page uses
them, but no missing helper was found relative to that document.

[Content.md](Content.md) is unsorted research and organisation records. No importer
or seed workflow tied to that file was found. Whether the listed organisations
already exist in the hosted database remains unknown. Importing the notes would
need record matching and source review; it is not an established requirement here.

## Current account documentation and verification

No material missing capability was identified against the three current account
documents in this review:

- **Avatars:** [Settings actions](../src/routes/account/settings/+page.server.ts),
  [image processing](../src/lib/server/avatar-image.ts),
  [avatar persistence](../src/lib/server/account-avatar.ts), root-layout renewal and
  [cron cleanup](../src/routes/api/cron/+server.ts) implement the described workflow.
  Account deletion and Microsoft Graph photo import are explicitly outside the
  documented implementation, so they are not counted as gaps.
- **Email changes:** [email-change helper](../src/lib/server/email-change.ts),
  confirmation routes and local template/config implement request/resend and
  partial/final confirmation handling. Hosted secure-email-change settings,
  redirect allowlists and delivery from both inboxes still need live verification.
- **Sessions:** [Security actions](../src/routes/account/security/+page.server.ts),
  [SessionSettings](../src/components/ui/SessionSettings.svelte) and the account-session
  migration implement listing and revocation. Access-token validity until expiry
  is an explicit documented limitation, not a missing immediate-revocation feature.

### Checks run for this review

| Check                        | Result                       |
| ---------------------------- | ---------------------------- |
| `npm run check`              | Passed: 0 errors, 0 warnings |
| `npm run test:avatars`       | Passed                       |
| `npm run test:email-changes` | Passed                       |
| `npm run test:sessions`      | Passed                       |
| `npm run test:cron`          | Passed                       |

These are local checks and targeted regression scripts, not full end-to-end
coverage of organisation workflows. Live SQL regression suites, browser flows,
email delivery, map service access and deployment configuration were not tested.
In particular, passing type checks does not detect the explicit UUID-to-number
conversion described in G01.

## Turning the findings into implementation tasks

For each accepted feature, use the current schema and authorization rules and
record concrete acceptance criteria. Start with G01 because it affects an existing
workflow. G02–G07 are practical workflow/UI candidates; G08, G09 and G11 require
explicit data-model or architecture choices. Update the source documents alongside
the eventual implementation so this analysis can be retired or refreshed rather
than becoming another stale proposal.
