export const PORTAL_LIFECYCLE_STATES = [
	'planned',
	'provisioned',
	'scope_configured',
	'seeding',
	'seed_review',
	'initial_release_approved',
	'operational',
	'suspended',
	'retired'
] as const;

export type PortalLifecycleState = (typeof PORTAL_LIFECYCLE_STATES)[number];

export interface PortalIdentity {
	portalId: string;
	portalKey: string;
	displayName: string;
	shortName: string;
	sponsorName: string;
	sponsorUrl: string | null;
	logoUrl: string | null;
	lifecycleState: PortalLifecycleState;
	configurationRevision: number;
}

export interface PortalManifest {
	portalId: string;
	portalKey: string;
}

export function portalManifestError(
	portal: Pick<PortalIdentity, 'portalId' | 'portalKey'> | null,
	manifest: Partial<PortalManifest>
): string | null {
	if (!manifest.portalId || !manifest.portalKey)
		return 'The deployment portal manifest is incomplete.';
	if (!portal) return 'The database portal identity is not configured.';
	if (portal.portalId.toLowerCase() !== manifest.portalId.toLowerCase())
		return 'The deployment portal ID does not match the database.';
	if (portal.portalKey !== manifest.portalKey)
		return 'The deployment portal key does not match the database.';
	return null;
}
