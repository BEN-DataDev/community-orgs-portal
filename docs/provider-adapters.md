# Provider adapter contract

The portal owns its domain and operational contracts. Supabase is the first
production adapter, not the type boundary for business workflows. The portable
database contract remains PostgreSQL because correctness depends on transactions,
constraints, functions, triggers and row-level security.

## Application ports

[`src/lib/server/providers/contracts.ts`](../src/lib/server/providers/contracts.ts)
defines the server-side ports:

- `DomainDatabase` invokes generated, typed PostgreSQL domain functions;
- `IdentityProvider` returns a provider-verified request identity and assurance;
- `AvatarProvider` owns account-profile compare-and-swap and private objects;
- `MaintenanceProvider` runs health, guest cleanup, abandoned-object cleanup and
  acquisition scheduling; and
- `ProviderDescriptor` publishes capabilities without implying unsupported
  portability.

[`src/lib/server/providers/supabase.ts`](../src/lib/server/providers/supabase.ts)
is the production implementation. Provider errors are normalised at this edge.
Route loaders and actions use `locals.providers.database` for domain RPCs; only
interactive Supabase Auth and browser data access retain the raw SDK client.

[`src/lib/server/providers/local.ts`](../src/lib/server/providers/local.ts) is an
in-memory proof adapter for the private-object/profile contract. It is deliberately
not selectable in a deployment and does not claim verified identity, durable
storage, managed secrets or production recovery.

## Capability matrix

`supported` means the checked-in adapter implements the capability. `external`
means the provider or deployment system owns it and the fleet records its reference
or outcome. `unsupported` means the adapter must fail closed for that use.

| Capability         | Supabase production adapter | Local/Docker proof adapter |
| ------------------ | --------------------------- | -------------------------- |
| PostgreSQL         | supported                   | supported                  |
| Verified identity  | supported                   | unsupported                |
| Private storage    | supported                   | proof implementation only  |
| Scheduler trigger  | external (Vercel)           | external/manual            |
| Secret references  | external                    | unsupported                |
| Backup and restore | external                    | external                   |
| Migrations         | supported                   | supported                  |

The TypeScript local descriptor reports its tested in-memory private storage as
`supported`. The fleet `docker_postgres` descriptor reports private storage as
`unsupported`, because Docker PostgreSQL alone does not supply an object service.

## Fleet adapter

The fleet-side `FleetProvider` protocol owns migration, establishment, bootstrap,
health and capability reporting. `supabase_postgres` and `docker_postgres` share
the PostgreSQL implementation while declaring different capabilities.

```sh
npm run fleet -- --manifest /operator/fleet.json capabilities
```

Supabase project creation, Auth-account creation, scheduling, secret resolution,
backup execution and restore execution remain explicit provider/deployment
operations. They are not application privileges and must be retained in the
operator evidence system. A restore check must target a new isolated portal.

## Adapter acceptance

Every new provider adapter must:

1. declare all seven capabilities using only `supported`, `external` or
   `unsupported`;
2. verify identity rather than trusting unverified cookie claims;
3. preserve PostgreSQL transaction, function and RLS semantics;
4. keep private objects private and use bounded signed access;
5. prove compare-and-swap behavior and ambiguous-failure cleanup safety;
6. run maintenance idempotently behind an authenticated scheduler trigger;
7. apply a manifest-pinned schema and fail closed on portal identity mismatch;
8. keep secret values out of manifests and fleet evidence; and
9. demonstrate backup/restore responsibility before production approval.

Run `npm run test:providers`, `npm run test:cron`, `npm run test:avatars`,
`npm run test:fleet` and `npm run test:fleet:db` for the checked-in contract and
isolation coverage.
