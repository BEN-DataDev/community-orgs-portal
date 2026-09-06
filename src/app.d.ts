// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces
import type { Session, User } from '@supabase/supabase-js';
import type { SafeSession, SessionAal } from '$lib/auth/session';
import type { TypedSupabaseClient } from '$lib/supabase-client';

declare global {
	namespace App {
		// interface Error {}
		interface Locals {
			supabase: TypedSupabaseClient;
			safeGetSession: () => Promise<SafeSession>;
			session: Session | null;
			user: User | null;
			/** Assurance level of the validated session; `null` when signed out. */
			aal: SessionAal | null;
			/** True for a `signInAnonymously()` session — see `$lib/auth/session`. */
			isAnonymous: boolean;
		}
		interface PageData {
			session: Session | null;
			aal: SessionAal | null;
			isAnonymous: boolean;
		}
		// interface PageState {}
		// interface Platform {}
	}
}

export {};
