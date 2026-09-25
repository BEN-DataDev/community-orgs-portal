import { error, fail } from '@sveltejs/kit';
import {
	isIngestionOperator,
	registrySeedPromotionInput,
	registrySeedQueueSchema,
	registrySeedTriageInput
} from '$lib/server/ingestion-review';
import type { Actions, PageServerLoad } from './$types';

const id = /^[1-9][0-9]*$/;

export const load: PageServerLoad = async ({ locals, url, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	if (!(await isIngestionOperator(locals.providers.database)))
		error(403, 'Data Steward access required.');
	const release = url.searchParams.get('release') ?? undefined;
	const version = url.searchParams.get('version') ?? undefined;
	const decision = url.searchParams.get('decision') ?? undefined;
	const offsetValue = Number(url.searchParams.get('offset') ?? '0');
	if ((release && !id.test(release)) || (version && !id.test(version)))
		error(400, 'Invalid queue ID.');
	if (decision && !['all', 'pending', 'include', 'exclude', 'defer', 'link'].includes(decision))
		error(400, 'Invalid decision filter.');
	if (!Number.isInteger(offsetValue) || offsetValue < 0 || offsetValue > 1_000_000)
		error(400, 'Invalid queue offset.');
	const result = await locals.providers.database.rpc('registry_seed_triage_queue', {
		p_release: release,
		p_version: version,
		p_decision: decision,
		p_offset: offsetValue
	});
	const parsed = registrySeedQueueSchema.safeParse(result.data);
	if (result.error || !parsed.success)
		error(result.error?.code === '42501' ? 403 : 500, 'Could not load registry seed candidates.');
	return { queue: parsed.data, decision: decision ?? 'all' };
};

export const actions: Actions = {
	triage: async ({ locals, request }) => {
		if (!(await isIngestionOperator(locals.providers.database)))
			error(403, 'Data Steward access required.');
		const parsed = registrySeedTriageInput.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success)
			return fail(400, { message: parsed.error.issues[0]?.message ?? 'Invalid triage decision.' });
		const input = parsed.data;
		const result = await locals.providers.database.rpc('save_registry_seed_triage', {
			p_version: input.version,
			p_revision: input.revision,
			p_decision: input.decision,
			p_target_candidate: input.targetKind === 'candidate' ? input.targetId : undefined,
			p_target_record: input.targetKind === 'record' ? input.targetId : undefined,
			p_note: input.note
		});
		if (result.error)
			return fail(result.error.code === '40001' ? 409 : result.error.code === '42501' ? 403 : 400, {
				message:
					result.error.code === '40001'
						? 'Another steward changed this candidate. Reload before saving.'
						: 'The candidate decision could not be saved.'
			});
		return { message: 'Registry candidate triage saved. Promotion remains a separate action.' };
	},
	promote: async ({ locals, request }) => {
		if (!(await isIngestionOperator(locals.providers.database)))
			error(403, 'Data Steward access required.');
		const parsed = registrySeedPromotionInput.safeParse(
			Object.fromEntries(await request.formData())
		);
		if (!parsed.success)
			return fail(400, { message: 'A release, candidate and promotion reason are required.' });
		const result = await locals.providers.database.rpc('promote_registry_seed_candidates', {
			p_release: parsed.data.release,
			p_versions: [parsed.data.version],
			p_reason: parsed.data.reason
		});
		if (result.error)
			return fail(result.error.code === '42501' ? 403 : 400, {
				message:
					'Promotion failed. Confirm the complete release, validation and include/link decision.'
			});
		return {
			message: `Candidate promoted to private ingestion run ${result.data}. Publication is still blocked.`
		};
	}
};
