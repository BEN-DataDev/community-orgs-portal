import { error } from '@sveltejs/kit';
import type { DomainDatabase } from '$lib/server/providers/contracts';
import { isSiteAdmin } from '$lib/server/authorization';
import { isIngestionOperator } from '$lib/server/ingestion-review';

/** Global task access never derives from an organisation's role level. */
export async function requireAdminAccess(
	client: DomainDatabase,
	userId: string | undefined,
	pathname: string
): Promise<void> {
	if (pathname !== '/admin' && !pathname.startsWith('/admin/')) return;
	if (!userId) error(403, 'You do not have access to this area.');
	if (pathname === '/admin/ingestion' || pathname.startsWith('/admin/ingestion/')) {
		if (!(await isIngestionOperator(client))) error(403, 'Ingestion operator access required.');
		return;
	}
	if (await isSiteAdmin(client, userId)) return;
	if ((pathname === '/admin' || pathname === '/admin/') && (await isIngestionOperator(client)))
		return;
	error(403, 'You do not have access to this area.');
}
