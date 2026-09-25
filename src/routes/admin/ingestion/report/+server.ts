import { error } from '@sveltejs/kit';
import { isIngestionOperator } from '$lib/server/ingestion-review';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ locals, url, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	if (!(await isIngestionOperator(locals.providers.database)))
		error(403, 'Ingestion operator access required.');
	const run = url.searchParams.get('run') ?? '';
	const baseline = url.searchParams.get('baseline') || undefined;
	if (
		![run, ...(baseline ? [baseline] : [])].every(
			(id) => /^[1-9][0-9]{0,18}$/.test(id) && BigInt(id) <= 9223372036854775807n
		)
	)
		error(400, 'Invalid run ID.');
	const result = await locals.providers.database.rpc('ingestion_change_report', {
		p_run: run,
		p_baseline: baseline
	});
	if (result.error) {
		if (result.error.code === '42501') error(403, 'Ingestion operator access required.');
		if (result.error.code === 'P0002') error(404, 'Run or baseline not found.');
		if (result.error.code === '22023')
			error(400, 'Choose an earlier baseline with the same source, resource and explicit scope.');
		error(500, 'Could not generate change report.');
	}
	return new Response(JSON.stringify(result.data, null, 2), {
		headers: {
			'content-type': 'application/json; charset=utf-8',
			'content-disposition': `attachment; filename="ingestion-run-${run}-changes.json"`,
			'x-content-type-options': 'nosniff'
		}
	});
};
