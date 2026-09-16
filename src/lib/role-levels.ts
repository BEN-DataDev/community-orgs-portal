/**
 * Per-organisation role levels, mirroring `community_orgs.roles.hierarchy_level`.
 * These roles are scoped to an organisation. Platform administrators are
 * separately appointed and receive effective owner-level access.
 *
 * This lives outside `$lib/server` because the UI needs it to decide whether to
 * render edit controls. It is a display concern only: the authoritative checks
 * are in `$lib/server/authorization.ts`.
 */
export const ROLE_LEVEL = {
	member: 1,
	moderator: 2,
	admin: 3,
	owner: 4
} as const;

/** The level required to change an organisation's records. */
export const EDITOR_LEVEL = ROLE_LEVEL.admin;
