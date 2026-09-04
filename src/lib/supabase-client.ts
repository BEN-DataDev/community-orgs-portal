import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from './db.types';

/**
 * The Supabase client type this project uses: typed against the generated
 * `Database` and pinned to the `community_orgs` schema, where every table
 * lives. The `public` schema — the client default — holds none of them.
 *
 * Note for the factory call sites in `hooks.server.ts` and `routes/+layout.ts`:
 * the installed @supabase/ssr (0.5.2) declares its return type with three
 * generic parameters, while supabase-js (2.108) now takes five. The arguments
 * bind to the wrong slots, `SchemaName` resolves to `never`, and every row type
 * collapses to `never` — which silently disables the type checking this alias
 * exists to provide. Those two call sites therefore cast to this type.
 *
 * Upgrading @supabase/ssr to 0.12.x (which requires supabase-js >= 2.112.4)
 * would align the declarations and let the casts be removed.
 */
export type TypedSupabaseClient = SupabaseClient<Database, 'community_orgs'>;
