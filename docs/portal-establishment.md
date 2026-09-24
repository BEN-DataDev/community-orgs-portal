# Portal identity establishment

The deployment and its database are bound by two stable values:

- `PORTAL_ID`: the UUID stored in `portal.configuration.portal_id`;
- `PORTAL_KEY`: the lowercase slug stored in `portal.configuration.portal_key`.

Every application request and authenticated cron health check returns `503` when
either manifest value is absent or differs from the database. Display names and
branding are deliberately not identity keys and may be changed by an administrator.

## Establish a database

After applying migrations, connect as the database owner and insert the one portal
identity. This is intentionally not available through the Data API or service-role
key.

```sql
insert into portal.configuration (
  portal_id,
  portal_key,
  display_name,
  short_name,
  sponsor_name,
  sponsor_url,
  logo_url,
  establishment_reason
) values (
  'replace-with-a-generated-uuid',
  'example-community',
  'Example Community Directory',
  'Example Directory',
  'Example Auspicing Organisation',
  'https://example.org.au',
  'https://example.org.au/portal-logo.svg',
  'Approved portal establishment record'
);
```

Set the same UUID and key as `PORTAL_ID` and `PORTAL_KEY` in the application and
worker deployment. A second configuration row is rejected by the database.

Before advancing to `scope_configured`, an administrator creates the first
authoritative postcode revision from **Admin → Portal scope**. Scope revisions are
append-only and record the inclusion-policy version, impact assessment, approval
reason and whether a re-baseline campaign is required. The existing deployment's
approved 23-postcode boundary is backfilled as revision 1 when PEG02 is applied to
an established database.

## Lifecycle administration

An authenticated platform administrator with the required MFA assurance advances
the lifecycle one state at a time:

```sql
select community_orgs.transition_portal_lifecycle(
  'provisioned',
  'Infrastructure checks completed',
  'OPS-123',
  1
);
```

The expected revision prevents overwriting a concurrent change. Moving to
`scope_configured` requires a non-empty scope evidence reference. Direct Data API
writes are denied, invalid jumps are rejected, and lifecycle events cannot be
updated or deleted. The lifecycle transition now requires an authoritative scope
revision; the text reference is retained only as a human-readable compatibility
field.
