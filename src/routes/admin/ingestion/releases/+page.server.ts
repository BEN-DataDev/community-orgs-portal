import { z } from 'zod';
import { error, fail } from '@sveltejs/kit';
import { isSiteAdmin } from '$lib/server/authorization';
import { isIngestionOperator, publicationReleaseQueueSchema } from '$lib/server/ingestion-review';
import type { Actions, PageServerLoad } from './$types';

const releaseDecisionInput = z.object({
	release: z.string().uuid(),
	revision: z.coerce.number().int().positive(),
	decision: z.enum(['approved', 'rejected']),
	note: z.string().trim().min(1).max(2000)
});

const releasePublicationInput = z.object({
	release: z.string().uuid(),
	revision: z.coerce.number().int().positive()
});

const policyInput = z.object({
	revision: z.coerce.number().int().positive(),
	ordinaryApproval: z.enum(['one_person', 'two_person']),
	reason: z.string().trim().min(1).max(2000)
});

async function access(locals: App.Locals) {
	const [canSteward, canAdmin] = await Promise.all([
		isIngestionOperator(locals.supabase),
		isSiteAdmin(locals.supabase, locals.user?.id)
	]);
	if (!canSteward && !canAdmin) error(403, 'Release authority required.');
	return { canSteward, canAdmin };
}

export const load: PageServerLoad = async ({ locals, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	const authority = await access(locals);
	const result = await locals.supabase.rpc('publication_release_queue');
	const parsed = publicationReleaseQueueSchema.safeParse(result.data);
	if (result.error || !parsed.success)
		error(result.error?.code === '42501' ? 403 : 500, 'Could not load publication releases.');
	return { ...authority, queue: parsed.data };
};

export const actions: Actions = {
	default: async ({ locals, request }) => {
		const authority = await access(locals);
		const form = await request.formData();
		const intent = form.get('intent');
		if (intent === 'policy') {
			if (!authority.canAdmin) error(403, 'Portal Administrator required.');
			const parsed = policyInput.safeParse(Object.fromEntries(form));
			if (!parsed.success)
				return fail(400, { intent, message: 'Choose a policy and provide a reason.' });
			const result = await locals.supabase.rpc('set_publication_approval_policy', {
				p_ordinary_requires_independent_approval: parsed.data.ordinaryApproval === 'two_person',
				p_expected_revision: parsed.data.revision,
				p_reason: parsed.data.reason
			});
			if (result.error)
				return fail(
					result.error.code === '40001' ? 409 : result.error.code === '42501' ? 403 : 400,
					{
						intent,
						message:
							result.error.code === '40001'
								? 'Policy changed. Reload and compare.'
								: 'Policy was not updated.'
					}
				);
			return { intent, message: 'Ordinary release approval policy updated.' };
		}
		if (intent === 'decision') {
			const parsed = releaseDecisionInput.safeParse(Object.fromEntries(form));
			if (!parsed.success)
				return fail(400, { intent, message: 'Choose a decision and provide a note.' });
			const result = await locals.supabase.rpc('decide_publication_release', {
				p_release: parsed.data.release,
				p_revision: parsed.data.revision,
				p_decision: parsed.data.decision,
				p_note: parsed.data.note
			});
			if (result.error)
				return fail(result.error.code === '42501' ? 403 : 409, {
					intent,
					message: result.error.message.includes('Submitter')
						? 'The submitter cannot provide the independent decision.'
						: 'Decision was not recorded. Reload the release and try again.'
				});
			return { intent, message: `Release ${parsed.data.decision}.` };
		}
		if (intent === 'publish') {
			if (!authority.canSteward) error(403, 'Data Steward required to publish.');
			const parsed = releasePublicationInput.safeParse(Object.fromEntries(form));
			if (!parsed.success) return fail(400, { intent, message: 'Invalid release revision.' });
			const result = await locals.supabase.rpc('publish_publication_release', {
				p_release: parsed.data.release,
				p_revision: parsed.data.revision
			});
			if (result.error)
				return fail(result.error.code === '42501' ? 403 : 409, {
					intent,
					message:
						'Publication was not applied. The frozen source, target or approval may have changed.'
				});
			return { intent, message: 'The exact approved release revision was published.' };
		}
		return fail(400, { message: 'Unknown release action.' });
	}
};
