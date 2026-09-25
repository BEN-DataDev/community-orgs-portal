import { env } from '$env/dynamic/private';
import type { DomainDatabase } from '$lib/server/providers/contracts';
import {
	PORTAL_LIFECYCLE_STATES,
	portalManifestError,
	type PortalIdentity,
	type PortalLifecycleState
} from '$lib/portal';

export class PortalIdentityError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'PortalIdentityError';
	}
}

/**
 * Load the database identity and bind it to this deployment's manifest. This
 * deliberately runs at the request boundary: serverless processes have no
 * reliable one-off startup phase, and a deployment must fail closed after a
 * database target or manifest changes.
 */
export async function requirePortalIdentity(client: DomainDatabase): Promise<PortalIdentity> {
	const { data, error } = await client.rpc('get_portal_identity');
	if (error) throw new PortalIdentityError(`Could not read the portal identity: ${error.message}`);
	if ((data?.length ?? 0) > 1)
		throw new PortalIdentityError('The database contains more than one portal identity.');

	const row = data?.[0];
	const lifecycleState = row?.lifecycle_state as PortalLifecycleState | undefined;
	if (row && !PORTAL_LIFECYCLE_STATES.includes(lifecycleState!))
		throw new PortalIdentityError('The database portal lifecycle state is invalid.');

	const portal: PortalIdentity | null = row
		? {
				portalId: row.portal_id,
				portalKey: row.portal_key,
				displayName: row.display_name,
				shortName: row.short_name,
				sponsorName: row.sponsor_name,
				sponsorUrl: row.sponsor_url,
				logoUrl: row.logo_url,
				lifecycleState: lifecycleState!,
				configurationRevision: row.configuration_revision,
				schemaVersion: row.schema_version,
				scopeRevisionId: row.scope_revision_id,
				scopeRevision: row.scope_revision,
				scopePostcodes: row.scope_postcodes ?? []
			}
		: null;
	const manifestError = portalManifestError(portal, {
		portalId: env.PORTAL_ID,
		portalKey: env.PORTAL_KEY
	});
	if (manifestError) throw new PortalIdentityError(manifestError);
	return portal!;
}
