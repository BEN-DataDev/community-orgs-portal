# Fleet operations

The fleet CLI is a control plane outside every portal database. It consumes a
versioned deployment manifest, keeps an inventory in local SQLite, invokes a
provider adapter, and creates hash-chained append-only operation evidence. It
does not store organisation data, source evidence, database URLs, tokens or
credential values.

Start from [`fleet/manifest.example.json`](../fleet/manifest.example.json). Keep
the real manifest in the operator repository or deployment system, not in this
application repository. Every database connection and application, worker or
bootstrap credential is an `env:`, `vault:`, `aws-sm:`, `gcp-sm:` or `azure-kv:`
reference. The bundled PostgreSQL adapter resolves only `env:` connection
references; production secret-manager resolution belongs in the operator
environment.

```sh
npm run fleet -- --manifest /operator/fleet.json validate
npm run fleet -- --manifest /operator/fleet.json inventory
npm run fleet -- --manifest /operator/fleet.json capabilities
npm run fleet -- --manifest /operator/fleet.json provision snowy-valleys \
  --operator operator@example.org --purpose OPS-142
npm run fleet -- --manifest /operator/fleet.json migrate snowy-valleys \
  --operator operator@example.org --purpose REL-2026-09-25
npm run fleet -- --manifest /operator/fleet.json health snowy-valleys \
  --operator operator@example.org --purpose CHECK-2026-09-25
```

`provision` applies repository migrations only through the manifest's target
schema version, establishes the immutable portal identity, optionally appoints
an already-created Auth account as the first Portal Administrator, and verifies
identity and schema. It is replay-safe. A database already bound to another
portal fails closed. `migrate` supports rolling upgrades because each portal can
pin an adjacent schema version independently.

`capabilities` reports the application-owned provider contract for every bundled
adapter. An `external` capability remains the deployment operator's responsibility;
`unsupported` must never be interpreted as a best-effort implementation. See
[provider adapters](provider-adapters.md).

The `supabase_postgres` adapter expects a Supabase-compatible database with its
Auth, Storage and extension schemas available. Project creation and the initial
Auth account remain provider operations. `docker_postgres` exists for isolated
acceptance environments and is not a production adapter; it explicitly lacks
verified identity, object storage and managed secret capabilities.

## Credential rotation

Rotate the value in the approved secret manager/provider first. Then move the
manifest/deployment to the new versioned reference and record the verified
handoff:

```sh
npm run fleet -- --manifest /operator/fleet.json rotate-credential snowy-valleys bootstrap \
  --new-secret-ref vault:community-portals/snowy-valleys/bootstrap@2 \
  --operator operator@example.org --purpose OPS-143
```

The CLI refuses the current reference, stores only the new reference and
revision, and records the operator and purpose. Run `health` with the rotated
connection/deployment before revoking the old provider-side version. This
two-step overlap avoids losing recovery access. Emergency provider-console use
must be followed by the same operation record with the incident reference.

## Audit and recovery

```sh
npm run fleet -- --manifest /operator/fleet.json export-audit \
  --output /approved-evidence/fleet-audit.json
```

The export contains inventory, credential references, success and failure
events, affected schema versions, and chain verification. Back up the SQLite
control file with the operator evidence store. It is a control-plane record,
not a secret store. Restore checks should use a new isolated deployment and a
new portal identity; never overwrite an operational portal to test recovery.

Run `npm run test:fleet` for the fast control-plane and audit regressions, and
`npm run test:fleet:db` for a disposable PostgreSQL acceptance test that applies
one pinned schema to two isolated databases, bootstraps a different first
administrator in each, rotates the second bootstrap reference and proves the
first portal was unchanged. The existing disposable-database suite continues to
validate the complete portal migration and governance chain.
