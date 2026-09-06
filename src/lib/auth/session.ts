import type { AuthenticatorAssuranceLevels, Session, User } from '@supabase/supabase-js';

/**
 * Supabase types this as `'aal1' | 'aal2' | (string & {})` so future levels do
 * not break consumers. Re-exported under a local name so the rest of the app
 * has one thing to import.
 */
export type AalLevel = AuthenticatorAssuranceLevels;

/**
 * The authenticator assurance level of the current session.
 *
 * `currentLevel` is what the caller has actually proved; `nextLevel` is the
 * highest they *could* reach with the factors on their account. The pairing is
 * what tells the two interesting cases apart:
 *
 * | current | next   | meaning                                     |
 * | ------- | ------ | ------------------------------------------- |
 * | `aal1`  | `aal1` | no MFA factor enrolled                      |
 * | `aal1`  | `aal2` | factor enrolled, challenge not yet passed   |
 * | `aal2`  | `aal2` | factor enrolled and verified this session   |
 * | `aal2`  | `aal1` | factor was removed; the JWT is stale        |
 */
export interface SessionAal {
	currentLevel: AalLevel | null;
	nextLevel: AalLevel | null;
}

export interface SafeSession {
	session: Session | null;
	user: User | null;
	aal: SessionAal | null;
	/** True for a `signInAnonymously()` session. Anonymous users hold the same
	 * `authenticated` Postgres role as everyone else, so this is the only thing
	 * distinguishing them. */
	isAnonymous: boolean;
}

/**
 * Does this session have an enrolled factor it has not yet satisfied?
 *
 * Note what this deliberately is not: a security boundary. Row-level security
 * refuses `aal1` tokens for enrolled users regardless of what the application
 * does. This exists so the app can send someone to the challenge page instead of
 * showing them an empty screen — Supabase's SSR guidance is explicit that an
 * unexpected AAL on the server is usually a closed tab or an abandoned
 * enrolment, not an attack, and should be handled with a redirect rather than a
 * 401.
 */
export function needsMfaChallenge(aal: SessionAal | null): boolean {
	return aal?.currentLevel === 'aal1' && aal.nextLevel === 'aal2';
}
